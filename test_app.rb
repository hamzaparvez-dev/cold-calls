#!/usr/bin/env ruby

# Simple test script to verify the application works
require 'bundler/setup'
require './client-acd-production.rb'

puts "Testing Twilio Dialer Application..."
puts "Environment: #{ENV['RACK_ENV'] || 'development'}"

# Test basic functionality
begin
  # Test environment variables
  required_vars = %w[twilio_account_sid twilio_account_token twilio_app_id twilio_caller_id MONGODB_URI]
  missing_vars = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }
  
  if missing_vars.any?
    puts "❌ Missing environment variables: #{missing_vars.join(', ')}"
    puts "Please set these in your .env file or environment"
    exit 1
  else
    puts "✅ All required environment variables are set"
  end
  
  # Test Twilio client initialization
  begin
    @client = Twilio::REST::Client.new(ENV['twilio_account_sid'], ENV['twilio_account_token'])
    account = @client.account
    puts "✅ Twilio client initialized successfully"
  rescue => e
    puts "❌ Twilio client initialization failed: #{e.message}"
    exit 1
  end
  
  # Test MongoDB connection
  begin
    db = URI.parse(ENV['MONGODB_URI'])
    db_name = db.path.gsub(/^\//, '')   
    @conn = Mongo::Connection.new(db.host, db.port).db(db_name)
    @conn.authenticate(db.user, db.password) unless (db.user.nil? || db.password.nil?)
    puts "✅ MongoDB connection established"
  rescue => e
    puts "❌ MongoDB connection failed: #{e.message}"
    puts "Make sure MongoDB is running and accessible"
    exit 1
  end
  
  puts "✅ All tests passed! Application is ready for deployment."
  
rescue => e
  puts "❌ Test failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
