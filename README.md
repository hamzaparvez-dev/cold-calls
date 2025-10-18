# Twilio Dialer with ACD (Automatic Call Distribution)

A production-ready Ruby/Sinatra application that provides a web-based softphone interface with automatic call distribution capabilities using Twilio's API.

## Features

- **Web-based Softphone**: Browser-based calling interface
- **Automatic Call Distribution**: Intelligent call routing to available agents
- **Queue Management**: Handle call queues when no agents are available
- **Real-time Updates**: WebSocket-based real-time status updates
- **Click-to-Dial**: Outbound calling functionality
- **Call Management**: Hold, unhold, voicemail drop capabilities
- **Agent Status Tracking**: Ready/Not Ready status management
- **Call Recording**: Automatic call recording
- **Production Ready**: Comprehensive error handling, logging, and security

## Quick Start

### Prerequisites

- Ruby 3.0+
- MongoDB (local or MongoDB Atlas)
- Twilio Account with phone number
- Node.js (for development)

### Installation

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd twilio-dialer/lightning-dialer
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your Twilio and MongoDB credentials
   ```

4. **Start MongoDB** (if running locally)
   ```bash
   mongod
   ```

5. **Run the application**
   ```bash
   bundle exec ruby client-acd-production.rb
   ```

6. **Access the application**
   Open http://localhost:5000 in your browser

## Environment Variables

Create a `.env` file with the following variables:

```bash
# Twilio Configuration
twilio_account_sid=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
twilio_account_token=your_auth_token_here
twilio_app_id=APxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
twilio_caller_id=+1234567890
twilio_queue_name=CustomerService
twilio_dqueue_url=https://your-domain.com/voice

# MongoDB Configuration
MONGODB_URI=mongodb://localhost:27017/twilio_dialer

# Optional Configuration
anycallerid=none
RACK_ENV=production
PORT=5000
LOG_LEVEL=INFO
```

## Twilio Setup

### 1. Get Twilio Credentials
- Account SID and Auth Token: https://twilio.com/user/account
- Phone Number: Purchase from Twilio Console
- TwiML App: Create in Dev Tools > TwiML Apps

### 2. Configure Webhooks
Update your Twilio phone number webhooks:
- Voice URL: `https://your-domain.com/voice`
- Status Callback: `https://your-domain.com/handledialcallstatus`

### 3. TwiML App Configuration
- Voice URL: `https://your-domain.com/dial`
- Status Callback: `https://your-domain.com/handledialcallstatus`

## Deployment Options

### Heroku
```bash
heroku create your-app-name
heroku addons:create mongolab:sandbox
heroku config:set twilio_account_sid=ACxxx...
# ... set other environment variables
git push heroku main
```

### Docker
```bash
docker-compose up -d
```

### VPS/Cloud Server
See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed instructions.

## API Endpoints

### Web Interface
- `GET /` - Main softphone interface
- `GET /token` - Twilio client token generation

### WebSocket
- `GET /websocket` - Real-time agent status updates

### Voice Handling
- `POST /voice` - Handle incoming calls
- `POST /dial` - Click-to-dial functionality
- `POST /handledialcallstatus` - Call status callbacks

### Agent Management
- `POST /track` - Update agent status
- `GET /status` - Get agent status
- `POST /setcallerid` - Set agent caller ID
- `GET /getcallerid` - Get agent caller ID

### Call Control
- `POST /request_hold` - Hold a call
- `POST /hold` - TwiML for hold music
- `POST /request_unhold` - Unhold a call
- `POST /send_to_agent` - Transfer to agent
- `POST /voicemail` - Voicemail drop

## Architecture

### Components
- **Sinatra Web Server**: Main application server
- **MongoDB**: Agent and call data storage
- **Twilio API**: Voice communication and call management
- **WebSockets**: Real-time communication
- **Background Thread**: Queue management and monitoring

### Data Models

#### Agents Collection
```javascript
{
  "_id": "agent_email@domain.com",
  "status": "Ready|NotReady|Ringing|DeQueing|Missed|LOGGEDOUT",
  "readytime": 1234567890.123,
  "currentclientcount": 1,
  "callerid": "+1234567890"
}
```

#### Calls Collection
```javascript
{
  "_id": "call_sid_from_twilio",
  "agent": "agent_email@domain.com",
  "status": "Ringing|Answered|Completed"
}
```

## Security Features

- **Input Validation**: All user inputs are validated and sanitized
- **CORS Configuration**: Proper cross-origin resource sharing
- **Environment Variables**: Sensitive data stored in environment variables
- **Error Handling**: Comprehensive error handling and logging
- **Rate Limiting**: Built-in protection against abuse

## Monitoring and Logging

- **Structured Logging**: JSON-formatted logs with different levels
- **Health Checks**: Built-in health check endpoints
- **Error Tracking**: Comprehensive error logging and reporting
- **Performance Monitoring**: Queue size and agent status monitoring

## Development

### Running Tests
```bash
bundle exec rspec  # If you add tests
```

### Code Style
```bash
rubocop  # If you add RuboCop
```

### Development Server
```bash
rerun 'ruby client-acd-production.rb'
```

## Troubleshooting

### Common Issues

1. **MongoDB Connection Errors**
   - Check MongoDB is running
   - Verify connection string
   - Check network access

2. **Twilio API Errors**
   - Verify Account SID and Auth Token
   - Check webhook URLs are accessible
   - Verify phone number ownership

3. **WebSocket Issues**
   - Check firewall settings
   - Verify WebSocket support
   - Check browser compatibility

### Logs
- Application logs: Check console output
- MongoDB logs: Check MongoDB log files
- Twilio logs: Check Twilio Console logs

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- Check the [Deployment Guide](DEPLOYMENT_GUIDE.md)
- Review the [Environment Setup](ENVIRONMENT_SETUP.md)
- Open an issue on GitHub

## Changelog

### v2.0.0 (Production Ready)
- Added comprehensive error handling
- Implemented input validation and sanitization
- Added security measures (CORS, protection)
- Updated dependencies with version constraints
- Added Docker support
- Created deployment guides
- Improved logging and monitoring
- Added health checks

### v1.0.0 (Original)
- Basic softphone functionality
- ACD queue management
- WebSocket real-time updates
- Click-to-dial capabilities