# The source for downloading gems from the official repository
source 'https://rubygems.org'

# Specify a stable Ruby version that is well-supported on Render
ruby '3.2.2'

# --- Core Application Gems ---
# Updated to modern, compatible versions
gem 'sinatra', '~> 3.0'
gem 'twilio-ruby', '~> 5.75' # Use a modern version compatible with new Ruby
gem 'json'
gem 'sinatra-websocket'
gem 'mongo', '~> 2.19'      # Modern MongoDB driver
gem 'bson_ext'
gem 'eventmachine', '~> 1.2'

# --- Server Gem for Production ---
# Puma is the industry-standard web server Render will use
gem 'puma', '~> 5.6'

# --- Utility Gem for Environment Variables ---
# Loads your .env file in your local development environment
gem 'dotenv'
