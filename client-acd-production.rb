require 'rubygems'
require 'sinatra'
require 'sinatra-websocket'
require 'twilio-ruby'
require 'json/ext'
require 'mongo'
require 'logger'
require 'dotenv/load'
require 'rack/protection'
require 'rack/cors'

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
  MONGODB_URI
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
mongohqdbstring = ENV['MONGODB_URI']
anycallerid = ENV['anycallerid'] || "none"

logger.info("Starting Twilio Dialer Application")
logger.info("Environment: #{ENV['RACK_ENV'] || 'development'}")

########### DB Setup  ###################
begin
  configure do
    # Use modern MongoDB driver
    @client = Mongo::Client.new(mongohqdbstring)
    @conn = @client.database
    set :mongo_connection, @conn
    logger.info("MongoDB connection established")
  end
rescue => e
  logger.error("Failed to connect to MongoDB: #{e.message}")
  exit 1
end

# Collections
mongoagents = settings.mongo_connection['agents']
mongocalls = settings.mongo_connection['calls']

################ TWILIO CONFIG ################
begin
  # Create a secure HTTP client that knows where to find the SSL certificates
  http_client = Twilio::HTTP::Client.new
  http_client.ssl_ca_file = '/etc/ssl/certs/ca-certificates.crt'

  # Initialize the Twilio client using our secure http_client
  @client = Twilio::REST::Client.new(account_sid, auth_token, http_client: http_client)

  account = @client.account
  @queues = account.queues.list
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
    @queue = account.queues.create(:friendly_name => qname)
    logger.info("Created new queue: #{qname}")
    queueid = @queue.sid
  end

  queue1 = account.queues.get(queueid)
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
    capability = Twilio::TwiML::VoiceResponse.new
    capability.dial do |dial|
        dial.client(client_name)
    end
    
    # This part is for generating a capability token, which is different from TwiML
    # For client-side JS SDK, you need a capability token
    capability = Twilio::Util::Capability.new account_sid, auth_token
    capability.allow_client_outgoing app_id
    capability.allow_client_incoming client_name
    token = capability.generate

    return token
  rescue => e
    logger.error("Failed to generate Twilio token: #{e.message}")
    status 500
    return "Token generation failed"
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

      begin
        mongoagents.update_one(
          {_id: clientname},
          {
            "$set" => {status: "LoggingIn", readytime: Time.now.to_f},
            "$inc" => {:currentclientcount => 1}
          },
          {upsert: true}
        )
        settings.sockets << ws
      rescue => e
        logger.error("Failed to update agent in database: #{e.message}")
        ws.close
      end
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

        begin
          mongoagents.update_one({_id: clientname}, {"$inc" => {currentclientcount: -1}})

          mongonewclientcount = mongoagents.find({_id: clientname}).first
          if mongonewclientcount && mongonewclientcount["currentclientcount"] < 1
            mongoagents.update_one({_id: clientname}, {"$set" => {status: "LOGGEDOUT"}})
          end
        rescue => e
          logger.error("Failed to update agent status on disconnect: #{e.message}")
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

    bestclient = getlongestidle(true, mongoagents)
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
        response.dial(
          timeout: "10",
          record: "record-from-answer",
          caller_id: callerid,
          method: "GET",
          action: "http://yardidhruv-touchpoint.cs62.force.com/Click2Dial/services/apexrest/TwilioCalls/TouchPoint?FromNumber=#{callerid}"
        ) do |dial|
          logger.debug("dialing client #{client_name}")

          agentinfo = {_id: sid, agent: client_name, status: "Ringing"}
          mongocalls.update_one({_id: sid}, {"$set" => agentinfo}, {upsert: true})

          dial.client(client_name)
        end
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
      mongosidinfo = mongocalls.find({_id: sid}).first
      if mongosidinfo
        mongoagent = mongosidinfo["agent"]
        mongoagents.update_one({_id: mongoagent}, {"$set" => {status: "Missed"}}, {upsert: false})
      end
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
    response.dial(
        record: "record-from-answer",
        caller_id: dial_id,
        method: "GET",
        action: "http://yardidhruv-touchpoint.cs62.force.com/Click2Dial/services/apexrest/TwilioCalls/TouchPoint?ToNumber=#{number}"
      ) do |dial|
        dial.number(number)
      end

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
    mongoagents.update_one(
      {_id: from},
      {"$set" => {status: status, readytime: Time.now.to_f}}
    )

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

    agentstatus = mongoagents.find({_id: from}).first
    if agentstatus
      agentstatus = agentstatus["status"]
    end
    return agentstatus || "Unknown"
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
    mongoagents.update_one({_id: from}, {"$set" => {callerid: callerid}})

    return ""
  rescue => e
    logger.error("Error in /setcallerid endpoint: #{e.message}")
    status 500
    "Error updating caller ID"
  end
end

get '/getcallerid' do
  begin
    from = sanitize_input(params[:from])

    unless validate_client_name(from)
      logger.warn("Invalid client name for getcallerid request: #{from}")
      status 400
      return "Invalid client name"
    end

    logger.debug("Getting callerid for #{from}")
    callerid = ""

    agent = mongoagents.find({_id: from}).first
    if agent && agent["callerid"]
      callerid = agent["callerid"]
    else
      callerid = caller_id
    end

    puts "returning callerid for #{from} = #{callerid}"
    return callerid
  rescue => e
    logger.error("Error in /getcallerid endpoint: #{e.message}")
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

    http_client = Twilio::HTTP::Client.new
    http_client.ssl_ca_file = '/etc/ssl/certs/ca-certificates.crt'
    local_client = Twilio::REST::Client.new(account_sid, auth_token, http_client: http_client)
    
    child_calls = local_client.calls.list(parent_call_sid: callsid)

    child_calls.each do |childcall|
      puts "Child Call SID: #{childcall.sid}"
      callsid = childcall.sid
    end

    customer_call = local_client.account.calls.get(callsid)
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

    http_client = Twilio::HTTP::Client.new
    http_client.ssl_ca_file = '/etc/ssl/certs/ca-certificates.crt'
    local_client = Twilio::REST::Client.new(account_sid, auth_token, http_client: http_client)

    if calltype == "Inbound"
      callsid = local_client.account.calls.get(callsid).parent_call_sid
    end

    puts "callsid = #{callsid} for calltype = #{calltype}"
    customer_call = local_client.account.calls.get(callsid)
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

    http_client = Twilio::HTTP::Client.new
    http_client.ssl_ca_file = '/etc/ssl/certs/ca-certificates.crt'
    local_client = Twilio::REST::Client.new(account_sid, auth_token, http_client: http_client)
    
    call = local_client.account.calls.get(callsid)
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
    response.dial do |dial|
        dial.client(target_agent)
    end

    puts response.to_s
    response.to_s
  rescue => e
    logger.error("Error in /send_to_agent endpoint: #{e.message}")
    status 500
    "Error sending to agent"
  end
end

# Helper method to get longest idle agent
def getlongestidle(callrouting, mongoagents)
  begin
    queryfor = []

    if callrouting == true
      queryfor = [{status: "Ready"}, {status: "DeQueing"}]
    else
      queryfor = [{status: "Ready"}]
    end

    mongoreadyagent = mongoagents.find(
      {"$or" => queryfor}
    ).sort(readytime: 1).first

    mongolongestidleagent = ""
    if mongoreadyagent
      mongolongestidleagent = mongoreadyagent["_id"]
    else
      mongolongestidleagent = nil
    end
    return mongolongestidleagent
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

      @members = queue1.members
      topmember = @members.list.first

      mongoreadyagents = mongoagents.count_documents({status: "Ready"})
      readycount = mongoreadyagents || 0

      qsize = account.queues.get(queueid).current_size

      if topmember
        bestclient = getlongestidle(false, mongoagents)
        if bestclient
          logger.info("Found best client - routing to #{bestclient} - setting agent to DeQueuing status")
          mongoagents.update_one({_id: bestclient}, {"$set" => {status: "DeQueuing"}})
          topmember.dequeue(url: ENV['twilio_dqueue_url'])
        else
          logger.debug("No Ready agents during queue poll # #{$sum}")
        end
      end

      settings.sockets.each{|s|
        msg = {:queuesize => qsize, :readyagents => readycount}.to_json
        logger.debug("Sending websocket #{msg}");
        s.send(msg)
      }
      logger.debug("run = #{$sum} #{Time.now} qsize = #{qsize} readyagents = #{readycount}")
    rescue => e
      logger.error("Error in queue management thread: #{e.message}")
      sleep(5) # Wait longer on error
    end
  end
end

Thread.abort_on_exception = true