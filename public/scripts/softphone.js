// Page loaded
//added comment
$(function() {

    // ** Application container ** //
    window.SP = {}

    // Global state
    SP.state = {};
    SP.state.callNumber = null;
    SP.state.calltype = "";
    SP.username = $('#client_name').text();
    SP.currentCall = null;  //instance variable for tracking current connection
    SP.requestedHold = false; //set if agent requested hold button
    SP.deviceReady = false; //track if Twilio Device is ready


 
    SP.functions = {};

        // Get a Twilio Client name and register with Twilio
    SP.functions.getTwilioClientName = function(sfdcResponse) {
        sforce.interaction.runApex('UserInfo', 'getUserName', '' , SP.functions.registerTwilioClient);
    }

   

    SP.functions.registerTwilioClient = function(response) {

      console.log("Registering with client name: " + response.result);

      // Twilio does not accept special characters in Client names
      var useresult = response.result;
      useresult = useresult.replace("@", "AT");
      useresult = useresult.replace(".", "DOT");
      SP.username = useresult;
      console.log("useresult = " + useresult);

      $.get("/token", {"client":SP.username})
        .done(function (token) {
          console.log("Token received, setting up Twilio Device...");
          try {
            // Use Twilio Client SDK (simpler API)
            if (typeof Twilio === 'undefined' || !Twilio.Device) {
              throw new Error("Twilio SDK not loaded. Please refresh the page.");
            }
            
            Twilio.Device.setup(token, {debug: true});
            console.log("Twilio Device setup initiated");
          } catch (error) {
            console.error("Error setting up Twilio Device:", error);
            alert("Failed to initialize phone system: " + (error.message || "Unknown error"));
            SP.deviceReady = false;
          }
        })
        .fail(function (xhr, status, error) {
          console.error("Failed to get token:", status, error);
          var errorMsg = xhr.responseText || "Server error: Unable to get authentication token. Please check server configuration.";
          alert("Phone System Error: " + errorMsg);
          SP.deviceReady = false;
        });

      $.get("/getcallerid", { "from":SP.username})
        .done(function(data) {
          if (data && data.trim() !== '') {
            $("#callerid-entry > input").val(data);
            console.log("Caller ID set to:", data);
          } else {
            console.warn("No caller ID returned from server");
          }
        })
        .fail(function (xhr, status, error) {
          console.error("Failed to get caller ID:", status, error);
          // Don't show alert for caller ID failure, just log it
          // The default caller ID from env variable will be used
        });

      SP.functions.startWebSocket();


    }

    // Old event handlers removed - now using setupDeviceEventHandlers() for Voice SDK 2.0
    // The new event handlers are set up in setupDeviceEventHandlers() function above


    SP.functions.startWebSocket = function() {
      // ** Agent Presence Stuff ** //
      console.log(".startWebSocket...");
     var wsaddress = 'wss://' + window.location.host  + "/websocket?clientname=" + SP.username

     var ws = new WebSocket(wsaddress);
        
      ws.onopen    = function()  { 
          console.log('websocket opened');
       };
      ws.onclose   = function()  { console.log('websocket closed'); }
      ws.onmessage = function(m) { 
        console.log('websocket message: ' +  m.data);
        
        var result = JSON.parse(m.data);

        $("#team-status .queues-num").text(result.queuesize);
        $("#team-status .agents-num").text(result.readyagents); 
      };

    }

    // ** UI Widgets ** //

    // Hook up numpad to input field
    $("div.number").bind('click',function(){
      //$("#number-entry > input").val($("#number-entry > input").val()+$(this).attr('Value'));
      //pass key without conn to a function
      SP.functions.handleKeyEntry($(this).attr('Value'));  

    });

    SP.functions.handleKeyEntry = function (key) {  
       if (SP.currentCall != null) {
          console.log("sending DTMF" + key);
          SP.currentCall.sendDigits(key);
       } else {
         $("#number-entry > input").val($("#number-entry > input").val()+key);
       }

    }

    //called when agent is not on a call
    SP.functions.setIdleState = function() {
        $("#action-buttons > .call").show();
        $("#action-buttons > .answer").hide();
        $("#action-buttons > .mute").hide();
        $("#action-buttons > .hold").hide();
        $("#action-buttons > .unhold").hide();
        $("#action-buttons > .hangup").hide();
        $("#action-buttons > .voicemail").hide();
        $('div.agent-status').hide();
        $("#number-entry > input").val("");
    }

    SP.functions.setRingState = function () {
        $("#action-buttons > .answer").show();
        $("#action-buttons > .call").hide();
        $("#action-buttons > .mute").hide();
        $("#action-buttons > .hold").hide();
        $("#action-buttons > .unhold").hide();
        $("#action-buttons > .hangup").hide();
        $("#action-buttons > .voicemail").hide();
    }

    SP.functions.setOnCallState = function() {

        $("#action-buttons > .answer").hide();
        $("#action-buttons > .call").hide();
        $("#action-buttons > .mute").show();
        $("#action-buttons > .voicemail").show();

        //can not hold outbound calls, so disable this
        if (SP.calltype == "Inbound") {
            $("#action-buttons > .hold").show();
        }

        $("#action-buttons > .hangup").show();
        $('div.agent-status').show();
    }

    // Hide caller info
    SP.functions.hideCallData = function() {
      $("#call-data").hide();
    }
    SP.functions.hideCallData();
    SP.functions.setIdleState();

    // Show caller info
    SP.functions.showCallData = function(callData) {
      $("#call-data > ul").hide();
      $(".caller-name").text(callData.callerName);
      $(".caller-number").text(callData.callerNumber);
      $(".caller-queue").text(callData.callerQueue);
      $(".caller-message").text(callData.callerMessage);

      if (callData.callerName) {
        $("#call-data > ul.name").show();
      }

      if (callData.callerNumber) {
        $("#call-data > ul.phone_number").show();
      }

      if (callData.callerQueue) {
        $("#call-data > ul.queue").show();
      }

      if (callData.callerMessage) {
        $("#call-data > ul.message").show();
      }

      $("#call-data").slideDown(400);
    }

    // Attach answer button to an incoming connection object
    SP.functions.attachAnswerButton = function(conn) {
      $("#action-buttons > button.answer").click(function() {
        conn.accept();
      }).removeClass('inactive').addClass("active");
    }

    SP.functions.detachAnswerButton = function() {
      $("#action-buttons > button.answer").unbind().removeClass('active').addClass("inactive");
    }

    SP.functions.attachMuteButton = function(conn) {
      $("#action-buttons > button.mute").click(function() {
        conn.mute();
        SP.functions.attachUnMute(conn);
      }).removeClass('inactive').addClass("active").text("Mute");
    }

    SP.functions.attachUnMute = function(conn) {
      $("#action-buttons > button.mute").click(function() {
        conn.unmute();
        SP.functions.attachMuteButton(conn);
      }).removeClass('inactive').addClass("active").text("UnMute");
    }

    SP.functions.detachMuteButton = function() {
      $("#action-buttons > button.mute").unbind().removeClass('active').addClass("inactive");
    }

    SP.functions.attachHoldButton = function(conn) {
      $("#action-buttons > button.hold").click(function() {
         console.dir(conn);
         SP.requestedHold = true;
         //can't hold outbound calls from Twilio client
         $.post("/request_hold", { "from":SP.username, "callsid":conn.parameters.CallSid, "calltype":SP.calltype }, function(data) {
             //Todo: handle errors
             //Todo: change status in future
             SP.functions.attachUnHold(conn, data);

          });

      }).removeClass('inactive').addClass("active").text("Hold");
    }
 // ---- VoiceMail --------- //
SP.functions.attachVoiceMailButton = function(conn) 
{
  $("#action-buttons > button.voicemail").click(function() 
  {
    //alert("Voicemail Functionality");
    //alert("CallSID------"+conn.parameters.CallSid);
    //alert("callerid------"+conn.parameters.From);
    //console.log("Voicemail Functionality");
    //alert("ABOUT TO POST--VOICEMAIL----");
    
    //console.log("ABOUT TO POST--VOICEMAIL----");
    $.post("/voicemail", {"callsid":conn.parameters.CallSid,"MachineDetection":"Enable","calid":$("#callerid-entry > input").val()}, function(data) 
    {
      alert("POST--VOICEMAIL----");
    });
  });
}
// ---- VoiceMail --------- //
     SP.functions.attachUnHold = function(conn, holdid) {
      $("#action-buttons > button.unhold").click(function() {
        //do ajax request to hold for the conn.id
         
         $.post("/request_unhold", { "from":SP.username, "callsid":holdid }, function(data) {
             //Todo: handle errors
             //Todo: change status in future
             //SP.functions.attachHoldButton(conn);
          });
        
      }).removeClass('inactive').addClass("active").text("UnHold").show();
    }
     
    SP.functions.detachHoldButtons = function() {
      $("#action-buttons > button.unhold").unbind().removeClass('active').addClass("inactive");
      $("#action-buttons > button.hold").unbind().removeClass('active').addClass("inactive");
    }
    SP.functions.updateAgentStatusText = function(statusCategory, statusText, inboundCall) {

      if (statusCategory == "ready") {
           $("#agent-status-controls > button.ready").prop("disabled",true); 
           $("#agent-status-controls > button.not-ready").prop("disabled",false); 
           $("#agent-status").removeClass();
           $("#agent-status").addClass("ready");
           $('#softphone').removeClass('incoming');
        
       }

      if (statusCategory == "notReady") {
           $("#agent-status-controls > button.ready").prop("disabled",false); 
           $("#agent-status-controls > button.not-ready").prop("disabled",true); 
           $("#agent-status").removeClass();
           $("#agent-status").addClass("not-ready");
           $('#softphone').removeClass('incoming');

      }

      if (statusCategory == "onCall") {
          $("#agent-status-controls > button.ready").prop("disabled",true); 
          $("#agent-status-controls > button.not-ready").prop("disabled",true); 
          $("#agent-status").removeClass();
          $("#agent-status").addClass("on-call");
          $('#softphone').removeClass('incoming');
      }

      if (inboundCall ==  true) { 
        //alert("call from " + statusText);
        $('#softphone').addClass('incoming');
        $("#number-entry > input").val(statusText);
      }

      //$("#agent-status > p").text(statusText);
    }

    // Call button will make an outbound call (click to dial) to the number entered 
    $("#action-buttons > button.call").click( function( ) {
      var phoneNumber = $("#number-entry > input").val();
      var callerId = $("#callerid-entry > input").val();
      
      // Validate phone number is not empty
      if (!phoneNumber || phoneNumber.trim() === '') {
        console.error("No phone number entered");
        alert("Please enter a phone number");
        return;
      }
      
      // Clean the phone number (remove spaces, dashes, parentheses, etc.)
      var cleanedNumber = phoneNumber.replace(/\s+/g, '').replace(/-/g, '').replace(/\(/g, '').replace(/\)/g, '');
      
      // Remove + prefix if present to normalize
      if (cleanedNumber.startsWith('+')) {
        cleanedNumber = cleanedNumber.substring(1);
      }
      
      // Format the number with country code
      if (cleanedNumber.length === 10) {
        // 10-digit US number, add +1
        cleanedNumber = '+1' + cleanedNumber;
      } else if (cleanedNumber.length === 11 && cleanedNumber.startsWith('1')) {
        // 11-digit number starting with 1, add +
        cleanedNumber = '+' + cleanedNumber;
      } else {
        // Other format, ensure it has + prefix
        cleanedNumber = '+' + cleanedNumber;
      }
      
      console.log("Attempting to call:", cleanedNumber);
      console.log("Caller ID:", callerId);
      
      // Check if Twilio Device is ready
      if (!Twilio.Device || !SP.deviceReady) {
        console.error("Twilio Device is not ready. Device exists:", !!Twilio.Device, "Device ready:", SP.deviceReady);
        alert("Phone system is not ready. Please wait a moment and try again.");
        return;
      }
      
      var params = {"PhoneNumber": cleanedNumber, "CallerId": callerId || ""};
      
      try {
        Twilio.Device.connect(params);
        console.log("Call initiated with params:", params);
      } catch (error) {
        console.error("Error initiating call:", error);
        alert("Error making call: " + (error.message || "Unknown error"));
      }
    });

    // Hang up button will hang up any active calls
    $("#action-buttons > button.hangup").click( function( ) {
      if (Twilio.Device) {
        Twilio.Device.disconnectAll();
      }
    });
    
    // Wire the ready / not ready buttons up to the server-side status change functions
    $("#agent-status-controls > button.ready").click( function( ) {
      $("#agent-status-controls > button.ready").prop("disabled",true); 
      SP.functions.ready();
    });

    $("#agent-status-controls > button.not-ready").click( function( ) {
      $("#agent-status-controls > button.not-ready").prop("disabled",true); 
      SP.functions.notReady();
    });

      $("#agent-status-controls > button.userinfo").click( function( ) {


    });



    // ** Twilio Client Stuff ** //
    // first register outside of sfdc


    if ( window.self === window.top ) {  
          console.log("Not in an iframe, assume we are using default client");
          var defaultclient = {}
          defaultclient.result = SP.username;
          SP.functions.registerTwilioClient(defaultclient);
      } else 
      {
        console.log("In an iframe, assume it is Salesforce");
        sforce.interaction.isInConsole(SP.functions.getTwilioClientName);   
      }
    //this will only be called inside of salesforce
    

    // Twilio Device event handlers (Client SDK)
    Twilio.Device.ready(function (device) {
      console.log("Twilio Device is ready");
      SP.deviceReady = true;
      if (typeof sforce !== 'undefined' && sforce.interaction && sforce.interaction.cti) {
        sforce.interaction.cti.enableClickToDial();
        sforce.interaction.cti.onClickToDial(startCall);
      }
      SP.functions.ready();
    });

    Twilio.Device.offline(function (device) {
      console.log("Twilio Device went offline");
      SP.deviceReady = false;
      if (typeof sforce !== 'undefined' && sforce.interaction && sforce.interaction.cti) {
        sforce.interaction.cti.disableClickToDial();
      }
      SP.functions.notReady();
      SP.functions.hideCallData();
    });

    Twilio.Device.error(function (error) {
      console.error("Twilio Device error:", error);
      SP.deviceReady = false;
      SP.functions.updateAgentStatusText("ready", error.message);
      SP.functions.hideCallData();
      alert("Twilio Device Error: " + (error.message || "Unknown error"));
    });

    Twilio.Device.disconnect(function (conn) {
      console.log("disconnecting...");
      SP.functions.updateAgentStatusText("ready", "Call ended");
      SP.state.callNumber = null;
      SP.functions.detachAnswerButton();
      SP.functions.detachMuteButton();
      SP.functions.detachHoldButtons();
      SP.functions.setIdleState(); 
      SP.currentCall = null;
      SP.functions.hideCallData();
      SP.functions.ready();
    });

    Twilio.Device.connect(function (conn) {
      console.dir(conn);
      var status = "";
      var callSid = conn.parameters ? conn.parameters.CallSid : null;
      console.log("callSid------>" + callSid);
      var callNum = null;
      if (conn.parameters && conn.parameters.From) {
        callNum = conn.parameters.From;
        status = "Call From: " + callNum;
        SP.calltype = "Inbound";
      } else {
        status = "Outbound call";
        SP.calltype = "Outbound";
      }
      SP.functions.updateAgentStatusText("onCall", status);
      SP.functions.setOnCallState();
      SP.functions.detachAnswerButton();
      SP.currentCall = conn;
      SP.functions.attachMuteButton(conn);
      SP.functions.attachHoldButton(conn, SP.calltype);
      SP.functions.attachVoiceMailButton(conn);
      $.post("/track", { "from":SP.username, "status":"OnCall" }, function(data) {});
    });

    Twilio.Device.incoming(function (conn) {
      if (typeof sforce !== 'undefined' && sforce.interaction) {
        sforce.interaction.setVisible(true);
      }
      var fromNumber = conn.parameters ? conn.parameters.From : null;
      SP.functions.updateAgentStatusText("ready", fromNumber, true);
      SP.functions.attachAnswerButton(conn);
      SP.functions.setRingState();
      if (SP.requestedHold == true) {
        SP.requestedHold = false;
        $("#action-buttons > button.answer").click();
      }
      var inboundnum = cleanInboundTwilioNumber(fromNumber);
      if (typeof sforce !== 'undefined' && sforce.interaction) {
        sforce.interaction.searchAndScreenPop(inboundnum, 'con10=' + inboundnum + '&con12=' + inboundnum + '&name_firstcon2=' + name,'inbound');
      }
    });

    Twilio.Device.cancel(function(conn) {
      console.log("Call canceled");
      SP.functions.detachAnswerButton();
      SP.functions.detachHoldButtons();
      SP.functions.hideCallData();
      SP.functions.notReady();
      SP.functions.setIdleState();
      $(".number").unbind();
      SP.currentCall = null;
    });

    $("#callerid-entry > input").change( function() {
        $.post("/setcallerid", { "from":SP.username, "callerid": $("#callerid-entry > input").val() });
    });



    // Set server-side status to ready / not-ready
    SP.functions.notReady = function() {
      $.post("/track", { "from":SP.username, "status":"NotReady" }, function(data) {
        SP.functions.updateStatus();
      });
    }

    SP.functions.ready = function() {

      $.post("/track", { "from":SP.username, "status":"Ready" }, function(data) {
          SP.functions.updateStatus();

      });
    }


    // Check the status on the server and update the agent status dialog accordingly
    SP.functions.updateStatus = function() {
      $.get("/status", { "from":SP.username}, function(data) {
        if (data == "NotReady" || data == "Missed") {
             SP.functions.updateAgentStatusText("notReady", "Not Ready")
         }

        if (data == "Ready") {
             SP.functions.updateAgentStatusText("ready", "Ready")
         }
      });

    }

    /******** GENERAL FUNCTIONS for SFDC  ***********************/

    function cleanInboundTwilioNumber(number) {
      //twilio inabound calls are passed with +1 (number). SFDC only stores 
      return number.replace('+1',''); 
    }

    function cleanFormatting(number) { 
            //changes a SFDC formatted US number, which would be 415-555-1212       
            return number.replace(' ','').replace('-','').replace('(','').replace(')','').replace('+','');
        }


    function startCall(response) { 
            
            //called onClick2dial
            sforce.interaction.setVisible(true);  //pop up CTI console
            var result = JSON.parse(response.result);  
            var cleanednumber = cleanFormatting(result.number);


            //alert("cleanednumber = " + cleanednumber);  
            params = {"PhoneNumber": cleanednumber, "CallerId": $("#callerid-entry > input").val()};
            if (Twilio.Device && SP.deviceReady) {
              Twilio.Device.connect(params);
            } else {
              alert("Phone system is not ready. Please wait a moment and try again.");
            }

    } 

    var saveLogcallback = function (response) {
        if (response.result) {
          console.log("saveLog result =" + response.result);
        } else {
          console.log("saveLog error = " + response.error);
        }
    };


    function saveLog(response) {
            
            console.log("saving log result, response:");
            var result = JSON.parse(response.result);

            console.log(response.result);
            
            var timeStamp = new Date().toString();
            timeStamp = timeStamp.substring(0, timeStamp.lastIndexOf(':') + 3);             
            var currentDate = new Date();           
            var currentDay = currentDate.getDate();
            var currentMonth = currentDate.getMonth()+1;
            var currentYear = currentDate.getFullYear();
            var dueDate = currentYear + '-' + currentMonth + '-' + currentDay;
            var saveParams = 'Subject=' + SP.calltype +' Call on ' + timeStamp;

            saveParams += '&Status=completed';                  
            saveParams += '&CallType=' + SP.calltype;  //should change this to reflect actual inbound or outbound
            saveParams += '&Activitydate=' + dueDate;
            saveParams += '&Phone=' + SP.state.callNumber;  //we need to get this from.. somewhere      
            saveParams += '&Description=' + "test description";   

            console.log("About to parse  result..");
            
            var result = JSON.parse(response.result);
            var objectidsubstr = result.objectId.substr(0,3);
            // object id 00Q means a lead.. adding this to support logging on leads as well as contacts.
            if(objectidsubstr == '003' || objectidsubstr == '00Q') {
                saveParams += '&whoId=' + result.objectId;                    
            } else {
                saveParams += '&whatId=' + result.objectId;            
            }
            
            console.log("save params = " + saveParams);
            sforce.interaction.saveLog('Task', saveParams, saveLogcallback);
  }
});