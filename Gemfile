# The source for downloading gems from the official repository
source 'https://rubygems.org'

# Specify the Ruby version to match Render's environment
ruby '3.3.0'

# --- Core Application Gems (Updated for Compatibility) ---
gem 'sinatra', '~> 3.0'
gem 'twilio-ruby', '~> 5.75' # CRITICAL: This line is the fix
gem 'jwt' # For manual JWT token construction if needed
gem 'json'
gem 'sinatra-websocket'
gem 'eventmachine', '~> 1.2'
gem 'dotenv'
gem 'bigdecimal'  # Required for Ruby 3.4+ compatibility

# --- Production & Security Gems ---
gem 'puma', '~> 5.6'
gem 'rack-protection'
gem 'rack-cors'

# --- Development-Only Gems ---
group :development, :test do
  gem 'rerun'
end