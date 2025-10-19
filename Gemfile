source 'https://rubygems.org'

# Specify Ruby version for Render compatibility
ruby '3.3.0'

# Core application gems - with compatible versions
gem 'sinatra', '~> 2.0'
gem 'twilio-ruby', '~> 4.0'  # Use older version compatible with our code
gem 'json', '~> 2.0'
gem 'sinatra-websocket', '~> 0.3'
gem 'mongo', '~> 2.0'  # Use modern MongoDB driver
gem 'bson_ext'  # Add BSON extension for performance
gem 'eventmachine', '~> 1.0'
gem 'bigdecimal'  # Fix for Ruby 3.4+ compatibility warning
gem 'base64'  # Fix for Ruby 3.4+ compatibility warning

# Production gems
gem 'puma', '~> 5.0'
gem 'rack', '~> 2.0'
gem 'dotenv', '~> 2.0'

# Security gems
gem 'rack-protection', '~> 2.0'
gem 'rack-cors', '~> 1.0'

group :development, :test do
  gem 'rerun', '~> 0.13'
end
