// MongoDB initialization script for Twilio Dialer
db = db.getSiblingDB('twilio_dialer');

// Create collections
db.createCollection('agents');
db.createCollection('calls');

// Create indexes for better performance
db.agents.createIndex({ "status": 1 });
db.agents.createIndex({ "readytime": 1 });
db.agents.createIndex({ "_id": 1 });

db.calls.createIndex({ "_id": 1 });
db.calls.createIndex({ "agent": 1 });
db.calls.createIndex({ "status": 1 });

// Insert sample data (optional)
db.agents.insertOne({
  "_id": "sample_agent",
  "status": "LOGGEDOUT",
  "readytime": new Date().getTime() / 1000,
  "currentclientcount": 0,
  "callerid": "+1234567890"
});

print("MongoDB initialization completed for Twilio Dialer");
