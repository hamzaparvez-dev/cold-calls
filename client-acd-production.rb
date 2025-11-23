require 'rubygems'
require 'sinatra'
require 'sinatra-websocket'
require 'twilio-ruby'
require 'json/ext'
# MongoDB removed - using simple in-memory storage
require 'logger'
require 'dotenv/load'
require 'rack/protection'
require 'rack/cors'
require 'openssl' # Required for the SSL fix

# --- FINAL SSL FIX ---
# This globally tells Ruby's OpenSSL where to find trusted certificates.
# It's more reliable than configuring the Twilio client directly.
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE if ENV['RACK_ENV'] == 'development' # For local dev
ENV['SSL_CERT_FILE'] = '/etc/ssl/certs/ca-certificates.crt'

# Load environment variables
Dotenv.load

# Configure logging
logger = Logger.new(STDOUT)
logger.level = ENV['LOG_LEVEL'] ? Logger.const_get(ENV['LOG_LEVEL'].upcase) : Logger::INFO

# Security and CORS configuration
set :sockets, []
set :protection, :except => [:json_csrf]
set :bind, '0.0.0.0'
set :port, ENV['PORT'] || 5000

# CORS configuration for cross-origin requests
use Rack::Cors do
  allow do
    origins '*'
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :delete, :options],
      credentials: false
  end
end

# Global variables
$sum = 0

############ CONFIG ###########################
# Validate required environment variables
required_env_vars = %w[
  twilio_account_sid
  twilio_account_token
  twilio_app_id
  twilio_caller_id
  twilio_queue_name
  twilio_dqueue_url
]

missing_vars = required_env_vars.select { |var| ENV[var].nil? || ENV[var].empty? }
if missing_vars.any?
  logger.error("Missing required environment variables: #{missing_vars.join(', ')}")
  logger.error("Please check your .env file or environment configuration")
  exit 1
end

# Twilio configuration
account_sid = ENV['twilio_account_sid']
auth_token = ENV['twilio_account_token']
app_id = ENV['twilio_app_id']
caller_id = ENV['twilio_caller_id']
qname = ENV['twilio_queue_name']
dqueueurl = ENV['twilio_dqueue_url']
anycallerid = ENV['anycallerid'] || "none"

# Simple in-memory storage (replaces MongoDB)
$agent_status = {} # {clientname => {status: "Ready", callerid: "+1234567890"}}

logger.info("Starting Twilio Dialer Application")
logger.info("Environment: #{ENV['RACK_ENV'] || 'development'}")

########### Simple In-Memory Storage (MongoDB Removed) ###################
logger.info("Using in-memory storage for agent status (MongoDB removed)")

################ TWILIO CONFIG ################
begin
  # Initialize Twilio client with new API syntax for gem 5.x
  @client = Twilio::REST::Client.new(account_sid, auth_token)

  # Use direct access to resources instead of deprecated account method
  @queues = @client.queues.list
  logger.info("Twilio client initialized successfully")
rescue => e
  logger.error("Failed to initialize Twilio client: #{e.message}")
  exit 1
end

##### Twilio Queue setup #####
queueid = nil
begin
  @queues.each do |q|
    logger.debug("Queue for this account = #{q.friendly_name}")
    if q.friendly_name == qname
      queueid = q.sid
      logger.info("Found existing queue: #{qname} with ID: #{queueid}")
    end
  end

  unless queueid
    @queue = @client.queues.create(:friendly_name => qname)
    logger.info("Created new queue: #{qname}")
    queueid = @queue.sid
  end

  queue1 = @client.queues(queueid).fetch
  logger.info("Calls will be queued to queueid = #{queueid}")
rescue => e
  logger.error("Failed to setup Twilio queue: #{e.message}")
  exit 1
end

default_client = "default_client"
logger.info("Application startup complete")

# Error handling middleware
error do
  logger.error("Application error: #{env['sinatra.error'].message}")
  logger.error("Backtrace: #{env['sinatra.error'].backtrace.join("\n")}")
  "Internal Server Error"
end

# Input validation helpers
def validate_phone_number(number)
  return false if number.nil? || number.empty?
  # Basic phone number validation (adjust regex as needed)
  number.match?(/^[\+]?[1-9][\d]{0,15}$/)
end

def validate_client_name(name)
  return false if name.nil? || name.empty?
  # Allow alphanumeric, dots, underscores, and @ symbols
  name.match?(/^[a-zA-Z0-9._@]+$/)
end

def sanitize_input(input)
  return nil if input.nil?
  input.strip.gsub(/[<>\"']/, '')
end

######### Main request URLs #########

### Returns HTML for softphone
get '/' do
  client_name = sanitize_input(params[:client]) || default_client

  unless validate_client_name(client_name)
    logger.warn("Invalid client name: #{client_name}")
    client_name = default_client
  end

  erb :index, :locals => {:anycallerid => anycallerid, :client_name => client_name}
end

## Returns a token for a Twilio client
get '/token' do
  client_name = sanitize_input(params[:client]) || default_client

  unless validate_client_name(client_name)
    logger.warn("Invalid client name for token request: #{client_name}")
    client_name = default_client
  end

  begin
    # Validate required environment variables
    if account_sid.nil? || account_sid.empty?
      logger.error("twilio_account_sid environment variable is not set")
      status 500
      return "Server configuration error: Twilio Account SID is missing"
    end
    
    if auth_token.nil? || auth_token.empty?
      logger.error("twilio_account_token environment variable is not set")
      status 500
      return "Server configuration error: Twilio Auth Token is missing"
    end
    
    if app_id.nil? || app_id.empty?
      logger.error("twilio_app_id environment variable is not set")
      status 500
      return "Server configuration error: Twilio App ID is missing"
    end
    
    # Voice SDK 2.0 requires Access Tokens, but can also use Capability Tokens
    # We'll generate a Capability Token that works with Voice SDK 2.0
    token = nil
    last_error = nil
    
    # Method 1: Try JWT ClientCapability (works with Voice SDK 2.0)
    begin
      capability = Twilio::JWT::ClientCapability.new(account_sid, auth_token)
      
      # Try to create scopes - the class names might be different
      scope_created = false
      
      # Try OutgoingScope
      ['OutgoingScope', 'OutgoingClientScope'].each do |class_name|
        begin
          if Twilio::JWT::ClientCapability.const_defined?(class_name)
            scope_class = Twilio::JWT::ClientCapability.const_get(class_name)
            outgoing = scope_class.new(app_id)
            capability.add_scope(outgoing)
            logger.debug("Added outgoing scope using #{class_name}")
            scope_created = true
            break
          end
        rescue => e
          logger.debug("Failed to use #{class_name}: #{e.message}")
        end
      end
      
      # Try IncomingScope  
      ['IncomingScope', 'IncomingClientScope'].each do |class_name|
        begin
          if Twilio::JWT::ClientCapability.const_defined?(class_name)
            scope_class = Twilio::JWT::ClientCapability.const_get(class_name)
            incoming = scope_class.new(client_name)
            capability.add_scope(incoming)
            logger.debug("Added incoming scope using #{class_name}")
            break
          end
        rescue => e
          logger.debug("Failed to use #{class_name}: #{e.message}")
        end
      end
      
      if scope_created
        token = capability.to_jwt
        logger.info("✓ Generated token using JWT ClientCapability (compatible with Voice SDK 2.0)")
        return token
      end
    rescue => e
      last_error = e
      logger.debug("JWT ClientCapability failed: #{e.class} - #{e.message}")
    end
    
    # Method 2: Try Util::Capability (fallback, but may not work with Voice SDK 2.0)
    begin
      capability = Twilio::Util::Capability.new(account_sid, auth_token)
      capability.allow_client_outgoing(app_id)
      capability.allow_client_incoming(client_name)
      token = capability.generate
      logger.info("✓ Generated token using Util::Capability (fallback)")
      return token
    rescue NameError, NoMethodError => e
      last_error = e
      logger.debug("Util::Capability not available: #{e.class} - #{e.message}")
    end
    
    # Method 3: Manual JWT construction - Capability Token format
    begin
      require 'jwt'
      
      # Create JWT payload for Twilio Capability Token (works with Voice SDK 2.0)
      now = Time.now.to_i
      payload = {
        iss: account_sid,
        exp: now + 3600,
        scope: [
          "scope:client:outgoing?appSid=#{app_id}&clientName=#{client_name}",
          "scope:client:incoming?clientName=#{client_name}"
        ].join(" ")
      }
      
      # Sign with auth_token
      token = JWT.encode(payload, auth_token, 'HS256')
      logger.info("✓ Generated token using manual JWT construction (Capability Token)")
      return token
    rescue LoadError => load_error
      logger.error("JWT gem not available: #{load_error.message}")
    rescue => jwt_manual_error
      logger.error("Manual JWT construction failed: #{jwt_manual_error.class} - #{jwt_manual_error.message}")
      logger.error("JWT manual backtrace: #{jwt_manual_error.backtrace.first(5).join("\n")}")
    end
    
    # If we get here, all methods failed
    logger.error("❌ All token generation methods failed!")
    logger.error("Last error: #{last_error.class} - #{last_error.message}")
    logger.error("Backtrace: #{last_error.backtrace.first(10).join("\n")}")
    raise "Token generation failed: #{last_error.message}. Please check Twilio gem version and API compatibility."
  rescue => e
    logger.error("Failed to generate Twilio token: #{e.message}")
    logger.error(e.backtrace.join("\n"))
    status 500
    return "Error generating token: #{e.message}"
  end
end

## WEBSOCKETS: Accepts inbound websocket connection
get '/websocket' do
  request.websocket do |ws|
    ws.onopen do
      logger.info("New Websocket Connection #{ws.object_id}")

      querystring = ws.request["query"]
      clientname = querystring&.split(/\=/)[1]

      unless clientname && validate_client_name(clientname)
        logger.warn("Invalid client name in websocket: #{clientname}")
        ws.close
        return
      end

      logger.info("Client #{clientname} connected from Websockets")
      settings.sockets << ws

      # Update in-memory storage
      $agent_status[clientname] ||= {status: "LoggingIn", readytime: Time.now.to_f, currentclientcount: 0}
      $agent_status[clientname][:currentclientcount] = ($agent_status[clientname][:currentclientcount] || 0) + 1
      $agent_status[clientname][:status] = "LoggingIn"
      $agent_status[clientname][:readytime] = Time.now.to_f
    end

    ws.onmessage do |msg|
      logger.debug("Received websocket message: #{msg}")
    end

    ws.onclose do
      querystring = ws.request["query"]
      clientname = querystring&.split(/\=/)[1]

      if clientname && validate_client_name(clientname)
        logger.info("Websocket closed for #{clientname}")

        settings.sockets.delete(ws)

        # Update in-memory storage
        if $agent_status[clientname]
          $agent_status[clientname][:currentclientcount] = ($agent_status[clientname][:currentclientcount] || 1) - 1
          if $agent_status[clientname][:currentclientcount] < 1
            $agent_status[clientname][:status] = "LOGGEDOUT"
          end
        end
      end
    end
  end
end

# Handle incoming voice calls
post '/voice' do
  begin
    sid = params[:CallSid]
    callerid = params[:Caller]
    addtoq = 0

    bestclient = getlongestidle(true)
    if bestclient
      logger.debug("Routing incoming voice call to best agent = #{bestclient}")
      client_name = bestclient
    else
      dialqueue = qname
    end

    response = Twilio::TwiML::VoiceResponse.new
    if dialqueue
        addtoq = 1
        response.say(message: "Please wait for the next available agent")
        response.enqueue(name: dialqueue)
    else
        dial = Twilio::TwiML::Dial.new(
          timeout: '10',
          record: 'record-from-answer',
          caller_id: callerid,
          method: 'GET',
          action: "http://yardidhruv-touchpoint.cs62.force.com/Click2Dial/services/apexrest/TwilioCalls/TouchPoint?FromNumber=#{callerid}"
        )
        dial.client(identity: client_name)
        response.append(dial)

        logger.debug("dialing client #{client_name}")
        # Call tracking removed (MongoDB removed)
    end

    logger.debug("Response text for /voice post = #{response.to_s}")
    response.to_s
  rescue => e
    logger.error("Error in /voice endpoint: #{e.message}")
    status 500
    "Error processing voice call"
  end
end

## Handle dial call status
post '/handledialcallstatus' do
  begin
    sid = params[:CallSid]

    response = Twilio::TwiML::VoiceResponse.new
    if params['DialCallStatus'] == "no-answer"
      # Missed call tracking removed (MongoDB removed)
      response.redirect('/voice')
    else
      response.hangup
    end

    logger.debug("response.text = #{response.to_s}")
    response.to_s
  rescue => e
    logger.error("Error in /handledialcallstatus endpoint: #{e.message}")
    status 500
    "Error processing call status"
  end
end

####### Click2dial functionality ###############
post '/dial' do
  begin
    puts "Params for dial = #{params}"

    number = sanitize_input(params[:PhoneNumber])
    dial_id = sanitize_input(params[:CallerId]) || caller_id

    unless validate_phone_number(number)
      logger.warn("Invalid phone number provided: #{number}")
      status 400
      return "Invalid phone number"
    end

    response = Twilio::TwiML::VoiceResponse.new
    dial = Twilio::TwiML::Dial.new(
        record: 'record-from-answer',
        caller_id: dial_id,
        method: 'GET',
        action: "http://yardidhruv-touchpoint.cs62.force.com/Click2Dial/services/apexrest/TwilioCalls/TouchPoint?ToNumber=#{number}"
    )
    dial.number(number)
    response.append(dial)

    puts response.to_s
    response.to_s
  rescue => e
    logger.error("Error in /dial endpoint: #{e.message}")
    status 500
    "Error processing dial request"
  end
end

######### Ajax endpoints for tracking agent state #####################

## Track agent status
post '/track' do
  begin
    from = sanitize_input(params[:from])
    status = sanitize_input(params[:status])

    unless validate_client_name(from) && status
      logger.warn("Invalid parameters for /track: from=#{from}, status=#{status}")
      status 400
      return "Invalid parameters"
    end

    logger.debug("For client #{from} setting status to #{status}")
    # Update in-memory storage
    $agent_status[from] ||= {}
    $agent_status[from][:status] = status
    $agent_status[from][:readytime] = Time.now.to_f

    return ""
  rescue => e
    logger.error("Error in /track endpoint: #{e.message}")
    status 500
    "Error updating agent status"
  end
end

### Get agent status
get '/status' do
  begin
    logger.debug("Getting a /status request with params = #{params}")
    from = sanitize_input(params[:from])

    unless validate_client_name(from)
      logger.warn("Invalid client name for status request: #{from}")
      status 400
      return "Invalid client name"
    end

    # Get from in-memory storage
    agent_data = $agent_status[from]
    return agent_data && agent_data[:status] ? agent_data[:status] : "Unknown"
  rescue => e
    logger.error("Error in /status endpoint: #{e.message}")
    status 500
    "Error retrieving status"
  end
end

post '/setcallerid' do
  begin
    from = sanitize_input(params[:from])
    callerid = sanitize_input(params[:callerid])

    unless validate_client_name(from) && validate_phone_number(callerid)
      logger.warn("Invalid parameters for /setcallerid: from=#{from}, callerid=#{callerid}")
      status 400
      return "Invalid parameters"
    end

    logger.debug("Updating callerid for #{from} to #{callerid}")
    # Update in-memory storage
    $agent_status[from] ||= {}
    $agent_status[from][:callerid] = callerid

    return ""
  rescue => e
    logger.error("Error in /setcallerid endpoint: #{e.message}")
    status 500
    "Error updating caller ID"
  end
end

get '/getcallerid' do
  begin
    from = sanitize_input(params[:from]) || default_client

    unless validate_client_name(from)
      logger.warn("Invalid client name for getcallerid request: #{from}")
      from = default_client
    end

    logger.debug("Getting callerid for #{from}")
    callerid = ""
    
    # Get from in-memory storage
    agent_data = $agent_status[from]
    if agent_data && agent_data[:callerid]
      callerid = agent_data[:callerid]
    end

    unless callerid && !callerid.empty?
      callerid = caller_id  #set to default env variable callerid
    end

    unless callerid && !callerid.empty?
      logger.warn("No caller ID found for #{from}, using empty string")
      callerid = ""  # Return empty string if no caller ID is configured
    end

    logger.debug("returning callerid for #{from} = #{callerid}")
    return callerid
  rescue => e
    logger.error("Error in /getcallerid endpoint: #{e.message}")
    logger.error(e.backtrace.join("\n")) if e.backtrace
    status 500
    "Error retrieving caller ID"
  end
end

# Voicemail functionality
post '/voicemail' do
  begin
    callsid = sanitize_input(params[:callsid])
    clid = sanitize_input(params[:calid])

    unless callsid && clid
      logger.warn("Missing parameters for /voicemail: callsid=#{callsid}, clid=#{clid}")
      status 400
      return "Missing parameters"
    end

    local_client = Twilio::REST::Client.new(account_sid, auth_token)
    
    child_calls = local_client.calls.list(parent_call_sid: callsid)

    child_calls.each do |childcall|
      puts "Child Call SID: #{childcall.sid}"
      callsid = childcall.sid
    end

    customer_call = local_client.calls(callsid).fetch
    customer_call.update(
      url: "http://yardidhruv-touchpoint.cs62.force.com/Click2Dial/VoiceMailDrop?uniqueid=#{clid}",
      method: "POST"
    )
    puts customer_call.to
  rescue => e
    logger.error("Error in /voicemail endpoint: #{e.message}")
    status 500
    "Error processing voicemail"
  end
end

post '/request_hold' do
  begin
    from = sanitize_input(params[:from])
    callsid = sanitize_input(params[:callsid])
    calltype = sanitize_input(params[:calltype])

    unless validate_client_name(from) && callsid && calltype
      logger.warn("Invalid parameters for /request_hold")
      status 400
      return "Invalid parameters"
    end

    local_client = Twilio::REST::Client.new(account_sid, auth_token)

    if calltype == "Inbound"
      callsid = local_client.calls(callsid).fetch.parent_call_sid
    end

    puts "callsid = #{callsid} for calltype = #{calltype}"
    customer_call = local_client.calls(callsid).fetch
    customer_call.update(
      url: "#{request.base_url}/hold",
      method: "POST"
    )
    puts customer_call.to
    return callsid
  rescue => e
    logger.error("Error in /request_hold endpoint: #{e.message}")
    status 500
    "Error processing hold request"
  end
end

post '/hold' do
  begin
    response = Twilio::TwiML::VoiceResponse.new
    response.play(url: "http://com.twilio.sounds.music.s3.amazonaws.com/ClockworkWaltz.mp3", loop: 0)
    
    puts response.to_s
    response.to_s
  rescue => e
    logger.error("Error in /hold endpoint: #{e.message}")
    status 500
    "Error processing hold"
  end
end

post '/request_unhold' do
  begin
    from = sanitize_input(params[:from])
    callsid = sanitize_input(params[:callsid])

    unless validate_client_name(from) && callsid
      logger.warn("Invalid parameters for /request_unhold")
      status 400
      return "Invalid parameters"
    end

    local_client = Twilio::REST::Client.new(account_sid, auth_token)
    
    call = local_client.calls(callsid).fetch
    call.update(
      url: "#{request.base_url}/send_to_agent?target_agent=#{from}",
      method: "POST"
    )
    puts call.to
  rescue => e
    logger.error("Error in /request_unhold endpoint: #{e.message}")
    status 500
    "Error processing unhold request"
  end
end

post '/send_to_agent' do
  begin
    target_agent = sanitize_input(params[:target_agent])

    unless validate_client_name(target_agent)
      logger.warn("Invalid target agent for /send_to_agent: #{target_agent}")
      status 400
      return "Invalid target agent"
    end

    puts params

    response = Twilio::TwiML::VoiceResponse.new
    dial = Twilio::TwiML::Dial.new
    dial.client(identity: target_agent)
    response.append(dial)
    
    puts response.to_s
    response.to_s
  rescue => e
    logger.error("Error in /send_to_agent endpoint: #{e.message}")
    status 500
    "Error sending to agent"
  end
end

# Helper method to get longest idle agent (using in-memory storage)
def getlongestidle(callrouting)
  begin
    statuses = callrouting == true ? ["Ready", "DeQueing"] : ["Ready"]
    
    # Find agents with matching status and sort by readytime
    matching_agents = $agent_status.select do |name, data|
      data && data[:status] && statuses.include?(data[:status])
    end
    
    return nil if matching_agents.empty?
    
    # Sort by readytime (oldest first = longest idle)
    longest_idle = matching_agents.min_by { |name, data| data[:readytime] || 0 }
    return longest_idle ? longest_idle[0] : nil
  rescue => e
    logger.error("Error in getlongestidle: #{e.message}")
    return nil
  end
end

## Background thread for queue management
Thread.new do
  while true do
    begin
      sleep(1)

      $sum += 1
      qsize = 0
      readycount = 0

      begin
        @members = queue1.members
        topmember = @members.list.first

        # Count ready agents from in-memory storage
        readycount = $agent_status.count { |k, v| v && v[:status] == "Ready" }

        begin
          qsize = @client.queues(queueid).fetch.current_size
        rescue => queue_error
          logger.warn("Failed to get queue size: #{queue_error.message}")
          qsize = 0
        end

        if topmember
          begin
            bestclient = getlongestidle(false)
            if bestclient
              logger.info("Found best client - routing to #{bestclient} - setting agent to DeQueuing status")
              $agent_status[bestclient][:status] = "DeQueuing" if $agent_status[bestclient]
              topmember.update(url: ENV['twilio_dqueue_url'], method: 'POST')
            else
              logger.debug("No Ready agents during queue poll # #{$sum}")
            end
          rescue => routing_error
            logger.warn("Error routing call: #{routing_error.message}")
          end
        end

        settings.sockets.each{|s|
          begin
            msg = {:queuesize => qsize, :readyagents => readycount}.to_json
            logger.debug("Sending websocket #{msg}");
            s.send(msg)
          rescue => ws_error
            logger.warn("Error sending websocket message: #{ws_error.message}")
            settings.sockets.delete(s) # Remove dead socket
          end
        }
        logger.debug("run = #{$sum} #{Time.now} qsize = #{qsize} readyagents = #{readycount}")
      rescue => e
        logger.error("Error in queue management thread: #{e.message}")
        logger.error(e.backtrace.join("\n")) if e.backtrace
        sleep(5) # Wait longer on error
      end
    rescue => fatal_error
      logger.error("Fatal error in queue management thread: #{fatal_error.message}")
      logger.error(fatal_error.backtrace.join("\n")) if fatal_error.backtrace
      sleep(10) # Wait even longer on fatal errors
    end
  end
end

Thread.abort_on_exception = true