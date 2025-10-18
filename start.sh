#!/bin/bash

# Exit on any error
set -e

echo "Starting Twilio Dialer Application..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Warning: .env file not found. Make sure environment variables are set."
fi

# Install dependencies
echo "Installing dependencies..."
bundle install

# Run database migrations or setup if needed
echo "Setting up database..."

# Start the application
echo "Starting application..."
exec bundle exec puma -p ${PORT:-5000} -e ${RACK_ENV:-production}
