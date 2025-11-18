require 'rubygems'
require 'sinatra'
require 'sinatra-websocket'
require 'twilio-ruby'
require 'json/ext' # required for .to_json
require 'mongo'
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG  #change to to get log level input from configuration

set :sockets, [] 
disable :protection  #necessary for ajax requests from a diffirent domain (like a SFDC iframe)

#global vars
$sum = 0   #number of iterations of checking the queue 

############ CONFIG ###########################
# Find these values at twilio.com/user/account
account_sid = ENV['twilio_account_sid']
auth_token =  ENV['twilio_account_token']
app_id =  ENV['twilio_app_id']
caller_id = ENV['twilio_caller_id']  #number your agents will click2dialfrom
qname = ENV['twilio_queue_name']
dqueueurl = ENV['twilio_dqueue_url']
mongohqdbstring = ENV['MONGODB_URI']
anycallerid = ENV['anycallerid'] || "none"   #If you set this in your ENV anycallerid=inline the callerid box will be displayed to users.  To use anycallerid (agents set their own caller id), your Twilio Account must be provisioned.  So default is false, agents wont' be able to use any callerid.

# Validate required environment variables at startup
missing_vars = []
missing_vars << "twilio_account_sid" if account_sid.nil? || account_sid.empty?
missing_vars << "twilio_account_token" if auth_token.nil? || auth_token.empty?
missing_vars << "twilio_app_id" if app_id.nil? || app_id.empty?
missing_vars << "MONGODB_URI" if mongohqdbstring.nil? || mongohqdbstring.empty?

if !missing_vars.empty?
  logger.error("Missing required environment variables: #{missing_vars.join(', ')}")
  logger.error("Please set these environment variables before starting the application")
  # Don't exit, but log the error - the endpoints will handle the errors gracefully
end 

########### DB Setup  ###################
configure do
  begin
    if mongohqdbstring && !mongohqdbstring.empty?
      db = URI.parse(mongohqdbstring)
      db_name = db.path.gsub(/^\//, '')   
      @conn = Mongo::Connection.new(db.host, db.port).db(db_name)
      @conn.authenticate(db.user, db.password) unless (db.user.nil? || db.password.nil?)
      set :mongo_connection, @conn
      logger.info("MongoDB connection established")
    else
      logger.error("MONGODB_URI environment variable is not set")
      set :mongo_connection, nil
    end
  rescue => e
    logger.error("Error connecting to MongoDB: #{e.message}")
    logger.error(e.backtrace.join("\n"))
    set :mongo_connection, nil
  end
end
# agents will be stored in 'agents' collection
if settings.mongo_connection
  mongoagents = settings.mongo_connection['agents']
  mongocalls = settings.mongo_connection['calls']
else
  logger.warn("MongoDB not connected, database features will not work")
  mongoagents = nil
  mongocalls = nil
end

##### end of db config #######


################ TWILLO CONFIG ################

#Twilio rest client - only initialize if credentials are available
begin
  if account_sid && !account_sid.empty? && auth_token && !auth_token.empty?
    @client = Twilio::REST::Client.new(account_sid, auth_token)
    account = @client.account
    @queues = account.queues.list

    ##### Twilio Queue setup:####
    # qname is a configuration vairable, but we need the queueid for this queue (we should have a helper method for this!!)
    queueid = nil
    if qname && !qname.empty?
      @queues.each do |q|
        logger.debug("Queue for this account = #{q.friendly_name}")
        if q.friendly_name == qname
          queueid = q.sid
          logger.info("Queueid = #{queueid} for #{q.friendly_name}")
        end
      end 

      unless queueid
        #didn't find qname, create it
        @queue = account.queues.create(:friendly_name => qname)
        logger.info("Created queue #{qname}")
        queueid = @queue.sid
      end

      ## all that work for a queueid... this should be replaced by a help library method!
      queue1 = account.queues.get(queueid)
      logger.info("Calls will be queued to queueid = #{queueid}")
    else
      logger.warn("twilio_queue_name not set, queue functionality will be limited")
    end
  else
    logger.warn("Twilio credentials not configured, Twilio features will not work")
    @client = nil
    queueid = nil
  end
rescue => e
  logger.error("Error initializing Twilio client: #{e.message}")
  logger.error(e.backtrace.join("\n"))
  @client = nil
  queueid = nil
end

## used when a 
default_client =  "default_client"

######### End of queue setup

logger.info("Starting up.. configuration complete")

#### thred




######### Main request Urls #########

### Returns HTML for softphone -- see html in /views/index.rb
get '/' do
  #for hmtl client
  client_name = params[:client]
  if client_name.nil?
        client_name = default_client
  end

  erb :index, :locals => {:anycallerid => anycallerid, :client_name => client_name}
end

## Returns a token for a Twilio client
get '/token' do
  begin
    client_name = params[:client]
    if client_name.nil?
      client_name = default_client
    end
    
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
    
    capability = Twilio::Util::Capability.new account_sid, auth_token
    # Create an application sid at twilio.com/user/account/apps and use it here
    capability.allow_client_outgoing app_id 
    capability.allow_client_incoming client_name
    token = capability.generate
    
    logger.debug("Generated token for client: #{client_name}")
    return token
  rescue => e
    logger.error("Failed to generate Twilio token: #{e.message}")
    logger.error(e.backtrace.join("\n"))
    status 500
    return "Error generating token: #{e.message}"
  end
end 
  
## WEBSOCKETS: Accepts a inbound websocket connection. Connection will be used to send messages to the browser, and detect disconnects
# 1. creates or updates agent in the db, and tracks how many broswers are connected with the "currentclientcount" parameter
# 2. changes agent status to "LOGGEDOUT" if no browsers are connected so we don't try to send calls to a non connected browser

get '/websocket' do 

  request.websocket do |ws|
    #we use .onopen to identify new clients
    ws.onopen do
      logger.info("New Websocket Connection #{ws.object_id}") 

      #query is wsclient=salesforceATuserDOTcom
      querystring = ws.request["query"]
      clientname = querystring.split(/\=/)[1]
      logger.info("Client #{clientname} connected from Websockets")
      #update database with list of clients
      mongoagents.update({_id: clientname} , { "$set" =>   {status: "LoggingIn",readytime: Time.now.to_f  },  "$inc"  =>  {:currentclientcount => 1}} , {upsert: true})
      settings.sockets << ws     
    end

    #currently don't recieve websocket messages from client 
    ws.onmessage do |msg|
      logger.debug("Received websocket message:  #{msg}")
    end

    
    ##websocket close
    ws.onclose do
      querystring = ws.request["query"]
      clientname = querystring.split(/\=/)[1]

      logger.info("Websocket closed for #{clientname}")

      settings.sockets.delete(ws)

      ###Reduce count of websocket connections for this client
      mongoagents.update({_id: clientname} , {  "$inc" => {currentclientcount: -1}});

      #If this username has 0 clients, change him to logged out in the database.
      mongonewclientcount = mongoagents.find_one({ _id: clientname})
      logger.debug("updating mongonewclientcount = #{mongonewclientcount}")
      if mongonewclientcount  
        if mongonewclientcount["currentclientcount"] < 1
           mongoagents.update({_id: clientname} , {  "$set" => {status: "LOGGEDOUT"}});
        end
      end
    end  ### End Websocket close


  end  #### End request.websocket 
end ### End get /websocket



# Handle incoming voice calls.. 
# You point your inbound Twilio phone number inside your Twilio account to this url, such as https://yourserver.com/voice
# Inbound calls will:
# 1. Look for agent who has been "ready" the longest  (getlongestidle function), send the call to this agent
# 2. If no agents are availbe, send the call to a queue (r.Enqueue(dialqueue))

post '/voice' do

    sid = params[:CallSid]
    callerid = params[:Caller]  
    addtoq = 0

    bestclient = getlongestidle(true, mongoagents)
    if bestclient
       logger.debug("Routing incomming voice call to best agent = #{bestclient}")
       client_name = bestclient
    else 
       dialqueue = qname
    end

    #if no client is choosen, route to queue
    response = Twilio::TwiML::Response.new do |r|  
        if dialqueue  #If this variable is set, we have no agents to route to
            addtoq = 1
            r.Say("Please wait for the next availible agent ")
            r.Enqueue(dialqueue)
        else      #send to best agent   
           # r.Dial(:timeout=>"10", :action=>"/handledialcallstatus", :callerId => callerid)  do |d|
           r.Dial(:timeout=>"10",:record=>"record-from-answer", :callerId => callerid, :method => "GET", :action=>"http://yardidhruv-touchpoint.cs62.force.com/Click2Dial/services/apexrest/TwilioCalls/TouchPoint?FromNumber=#{callerid}")  do |d| 
                logger.debug("dialing client #{client_name}")

                agentinfo = { _id: sid, agent: client_name, status: "Ringing" }
                sidinsert = mongocalls.update({_id: sid},  agentinfo, {upsert: true})

                d.Client client_name   
            end
        end
    end
    logger.debug("Response text for /voice post = #{response.text}")
    #update clients with new info, route calls if any
    #getqueueinfo(mongoagents,logger, queueid, addtoq)
    response.text
end


## This is called after an agent is sent a call (based on the :action parameter) - if an agent has missed a call change their status in the database
post '/handledialcallstatus' do
  sid = params[:CallSid]

  if params['DialCallStatus'] == "no-answer"
    mongosidinfo = {}
    mongosidinfo = mongocalls.find_one ({_id: sid})
    if mongosidinfo
        mongoagent = mongosidinfo["agent"]   
        mongoagents.update({_id: mongoagent}, { "$set" => {status:  "Missed"}}, {upsert: false})
    end

    response = Twilio::TwiML::Response.new do |r| 
        ## Change agent status for agents that missed calls
        r.Redirect('/voice')
    end
  else
    response = Twilio::TwiML::Response.new do |r| 
        ## Change agent status for agents that missed calls
        r.Hangup
    end
  end

  logger.debug("response.text  = #{response.text}")
  response.text
end


#######  This is called when agents click2dial ###############
# In Twilio, you set up a Twiml App, by going to Account -> Dev Tools - > Twiml Apps.  The app created here gives you the twilio_app_id requried for config.
# You then point the voice url for that app id to this url, such as "https://yourserver.com/dial" 
# This method will be called when a client clicks

post '/dial' do
    puts "Params for dial = #{params}"
    
    number = params[:PhoneNumber]
    dial_id = params[:CallerId] || caller_id


    response = Twilio::TwiML::Response.new do |r|
        # outboudn dialing (from client) must have a :callerId 
        # Yet to Recording feature and Callduration tracking 
       # r.Dial :callerId => dial_id do |d|
        r.Dial(:record=>"record-from-answer", :callerId => dial_id, :method => "GET", :action=>"http://yardidhruv-touchpoint.cs62.force.com/Click2Dial/services/apexrest/TwilioCalls/TouchPoint?ToNumber=#{number}")  do |d|
          d.Number number
        end
    end
    puts response.text
    response.text
end
######### End of Twilio methods

######### Ajax stuff for tracking agent state.  ##################### 
# DB will be ajax requests from the browser, such as changing from ready to not ready

## /track takes a parameter "status" and updates the "from" client sending it
post '/track' do
    from = params[:from]
    status = params[:status]

    logger.debug("For client #{from} settings status to #{status}")
    mongoagents.update({_id: from} , { "$set" =>   {status: status,readytime: Time.now.to_f}})

    return ""
end


### /status returns status for a particular client.  Ajax clients query the server in certain cases to get their status
get '/status' do
    logger.debug("Getting a /status request with params = #{params}")
    from = params[:from]

    agentstatus = mongoagents.find_one ({_id: from})
    if agentstatus
       agentstatus = agentstatus["status"]
    end
    return agentstatus
end

post '/setcallerid' do
    from = params[:from]
    callerid = params[:callerid]

    logger.debug("Updating callerid for #{from} to #{callerid}")
    mongoagents.update({_id: from} , { "$set" =>   {callerid: callerid}})

    return ""
end


get '/getcallerid' do
  begin
    from = params[:from]
    if from.nil?
      from = default_client
    end

    logger.debug("Getting callerid for #{from}")
    callerid = ""
    
    begin
      if mongoagents
        agent = mongoagents.find_one ({_id: from})
        if agent && agent["callerid"]
          callerid = agent["callerid"]
        end
      else
        logger.warn("MongoDB not connected, cannot retrieve caller ID from database")
      end
    rescue => e
      logger.warn("Error querying MongoDB for callerid: #{e.message}")
    end

    unless callerid && !callerid.empty?
      callerid = caller_id  #set to default env variable callerid
    end

    unless callerid && !callerid.empty?
      logger.warn("No caller ID found for #{from}, using default")
      callerid = ""  # Return empty string if no caller ID is configured
    end

    logger.debug("returning callerid for #{from} = #{callerid}")
    return callerid
  rescue => e
    logger.error("Error in /getcallerid endpoint: #{e.message}")
    logger.error(e.backtrace.join("\n"))
    status 500
    return ""
  end
end

#ajax request from Web UI, acccepts a casllsid, do a REST call to redirect to /hold
post '/voicemail' do
    callsid = params[:callsid]  #call sid the agent has for their leg
     clid = params[:calid]
    @client = Twilio::REST::Client.new(account_sid, auth_token)
    # child_calls = @client.calls.list(parent_call_sid=callsid)
	child_calls = @client.calls.list parent_call_sid: callsid
     child_calls.each do |childcall|
        puts "Child Call SID: #{childcall.sid}"
        callsid=childcall.sid
	
	#answeredby = childcall.answered_by
     end
	#if answeredby == "human"
	    customer_call = @client.account.calls.get(callsid)
	    # dl_id = "13614944241"
	    dl_id = clid
	    customer_call.update(:url => "http://yardidhruv-touchpoint.cs62.force.com/Click2Dial/VoiceMailDrop?uniqueid=#{dl_id}",
			 :method => "POST")  
	    puts customer_call.to
	#end
end

post '/request_hold' do
    from = params[:from]  #agent name
    callsid = params[:callsid]  #call sid the agent has for their leg
    calltype = params[:calltype]

    @client = Twilio::REST::Client.new(account_sid, auth_token)
    if calltype == "Inbound"  #get parentcallsid
      callsid = @client.account.calls.get(callsid).parent_call_sid  #parent callsid is the customer leg of the call for inbound
    end
    puts "callsid = #{callsid} for calltype = #{calltype}"
    customer_call = @client.account.calls.get(callsid)
    customer_call.update(:url => "#{request.base_url}/hold",
                 :method => "POST")  
    puts customer_call.to
    return callsid
end

#Twiml response for hold, currently uses Monkey as hold music
post '/hold' do
    response = Twilio::TwiML::Response.new do |r|
      r.Play "http://com.twilio.sounds.music.s3.amazonaws.com/ClockworkWaltz.mp3", :loop=>0 
    end

    puts response.text
    response.text
end

## Ajax post request that retrieves from hold
post '/request_unhold' do
    from = params[:from]
    callsid = params[:callsid]  #this should be a valid call sid to  "unhold"

    @client = Twilio::REST::Client.new(account_sid, auth_token)

    call = @client.account.calls.get(callsid)
    call.update(:url => "#{request.base_url}/send_to_agent?target_agent=#{from}",
                 :method => "POST")  
    puts call.to
end

post '/send_to_agent' do
   target_agent = params[:target_agent]
   puts params

   #todo: update agent status from here - ie hold
   response = Twilio::TwiML::Response.new do |r|
      r.Dial do |d|
        d.Client target_agent
      end 
   end

   puts response.text
   response.text  

end

#Method that gets all "Ready" agents, sorts by longest idle (ie, the first availible) 
# If callrouting == true, this function is being called from voice routing, and we want to select a "Ready" agent or a "DeQueing" agent

def getlongestidle (callrouting, mongoagents) 

   queryfor = []

   if callrouting == true
     queryfor = [ {status: "Ready"}, status: "DeQueing"]
   else
     queryfor = [ {status: "Ready"} ]
   end

   mongoreadyagent =  mongoagents.find_one( { "$query" => { "$or" => queryfor } , "$orderby" => {readytime: 1}  } )

   mongolongestidleagent = ""
   if mongoreadyagent
      mongolongestidleagent = mongoreadyagent["_id"]
   else
      mongolongestidleagent = nil
   end 
   return mongolongestidleagent

end



## Thread that polls to get current queue size, routes call if availible, and updates websocket clients with new info
Thread.new do 
   while true do
     sleep(1)
 
     $sum += 1  
     qsize = 0  
     account_sid = ENV['twilio_account_sid']
     auth_token =  ENV['twilio_account_token']
     qname = ENV['twilio_queue_name']

     @members = queue1.members
     topmember =  @members.list.first 

     mongoreadyagents = mongoagents.find({ status: "Ready"}).count()
     readycount = mongoreadyagents || 0

     qsize =  account.queues.get(queueid).current_size
    
      if topmember #only check for availible agent if there is a caller in queue
        
        bestclient = getlongestidle(false, mongoagents)
        if bestclient
          logger.info("Found best client - routing to #{bestclient} - setting agent to DeQueuing status so they aren't sent another call from the queue")
          mongoagents.update({_id: bestclient} , { "$set" =>   {status: "DeQueing" }  } )   
          topmember.dequeue(ENV['twilio_dqueue_url'])
        else 
          logger.debug("No Ready agents during queue poll # #{$sum}")
        end
      end 

      settings.sockets.each{|s| 
        msg =  { :queuesize => qsize, :readyagents => readycount}.to_json
        logger.debug("Sending webocket #{msg}");
        s.send(msg) 
      } 
     logger.debug("run = #{$sum} #{Time.now} qsize = #{qsize} readyagents = #{readycount}")
  end
end

Thread.abort_on_exception = true
