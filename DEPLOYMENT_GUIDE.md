# Twilio Dialer - Production Deployment Guide

## Overview
This guide will help you deploy the Twilio Dialer application to production with proper security, monitoring, and configuration.

## Prerequisites

### 1. Twilio Account Setup
- Create a Twilio account at https://twilio.com
- Purchase a phone number for caller ID
- Create a TwiML App in Dev Tools > TwiML Apps
- Note down your Account SID, Auth Token, and App SID

### 2. MongoDB Setup
- Set up MongoDB Atlas (recommended) or self-hosted MongoDB
- Create a database for the application
- Note down the connection URI

### 3. Environment Variables
Create a `.env` file in the lightning-dialer directory:

```bash
# Twilio Configuration
twilio_account_sid=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
twilio_account_token=your_auth_token_here
twilio_app_id=APxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
twilio_caller_id=+1234567890
twilio_queue_name=CustomerService
twilio_dqueue_url=https://your-domain.com/voice

# MongoDB Configuration
MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/twilio_dialer

# Optional Configuration
anycallerid=none
RACK_ENV=production
PORT=5000
LOG_LEVEL=INFO
SECRET_KEY=your_secret_key_here
```

## Deployment Options

### Option 1: Heroku Deployment

1. **Install Heroku CLI**
   ```bash
   # macOS
   brew install heroku/brew/heroku
   
   # Or download from https://devcenter.heroku.com/articles/heroku-cli
   ```

2. **Create Heroku App**
   ```bash
   cd lightning-dialer
   heroku create your-app-name
   ```

3. **Add MongoDB Add-on**
   ```bash
   heroku addons:create mongolab:sandbox
   ```

4. **Set Environment Variables**
   ```bash
   heroku config:set twilio_account_sid=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   heroku config:set twilio_account_token=your_auth_token_here
   heroku config:set twilio_app_id=APxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   heroku config:set twilio_caller_id=+1234567890
   heroku config:set twilio_queue_name=CustomerService
   heroku config:set twilio_dqueue_url=https://your-app-name.herokuapp.com/voice
   heroku config:set anycallerid=none
   heroku config:set RACK_ENV=production
   heroku config:set LOG_LEVEL=INFO
   ```

5. **Deploy**
   ```bash
   git add .
   git commit -m "Initial deployment"
   git push heroku main
   ```

### Option 2: Docker Deployment

1. **Create Dockerfile**
   ```dockerfile
   FROM ruby:3.0-alpine
   
   RUN apk add --no-cache build-base
   
   WORKDIR /app
   COPY Gemfile Gemfile.lock ./
   RUN bundle install
   
   COPY . .
   
   EXPOSE 5000
   
   CMD ["bundle", "exec", "puma", "-p", "5000", "-e", "production"]
   ```

2. **Build and Run**
   ```bash
   docker build -t twilio-dialer .
   docker run -p 5000:5000 --env-file .env twilio-dialer
   ```

### Option 3: VPS Deployment (Ubuntu/CentOS)

1. **Install Dependencies**
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install ruby ruby-dev build-essential mongodb
   
   # CentOS/RHEL
   sudo yum install ruby ruby-devel gcc mongodb-server
   ```

2. **Install Application**
   ```bash
   cd /opt
   git clone your-repo twilio-dialer
   cd twilio-dialer/lightning-dialer
   bundle install
   ```

3. **Create Systemd Service**
   ```bash
   sudo nano /etc/systemd/system/twilio-dialer.service
   ```
   
   ```ini
   [Unit]
   Description=Twilio Dialer Application
   After=network.target mongodb.service
   
   [Service]
   Type=simple
   User=www-data
   WorkingDirectory=/opt/twilio-dialer/lightning-dialer
   ExecStart=/usr/bin/bundle exec puma -p 5000 -e production
   Restart=always
   Environment=RACK_ENV=production
   EnvironmentFile=/opt/twilio-dialer/lightning-dialer/.env
   
   [Install]
   WantedBy=multi-user.target
   ```

4. **Start Service**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable twilio-dialer
   sudo systemctl start twilio-dialer
   ```

## Security Considerations

### 1. Environment Variables
- Never commit `.env` files to version control
- Use strong, unique values for all secrets
- Rotate credentials regularly

### 2. Network Security
- Use HTTPS in production
- Configure firewall rules
- Use VPN for database access if possible

### 3. Application Security
- Input validation is implemented
- CORS is configured
- Rate limiting should be added for production

### 4. Database Security
- Use MongoDB authentication
- Enable SSL/TLS for database connections
- Regular backups

## Monitoring and Logging

### 1. Application Monitoring
- Set up application performance monitoring (APM)
- Monitor error rates and response times
- Set up alerts for critical issues

### 2. Log Management
- Centralize logs using services like Loggly, Papertrail, or ELK stack
- Set up log rotation
- Monitor for security events

### 3. Health Checks
- Implement health check endpoints
- Monitor database connectivity
- Monitor Twilio API connectivity

## Twilio Configuration

### 1. Webhook URLs
Update your Twilio phone number webhooks:
- Voice URL: `https://your-domain.com/voice`
- Status Callback URL: `https://your-domain.com/handledialcallstatus`

### 2. TwiML App Configuration
- Voice URL: `https://your-domain.com/dial`
- Status Callback URL: `https://your-domain.com/handledialcallstatus`

## Testing

### 1. Local Testing
```bash
# Start MongoDB
mongod

# Start application
cd lightning-dialer
bundle install
bundle exec ruby client-acd-production.rb
```

### 2. Production Testing
- Test incoming calls
- Test click-to-dial functionality
- Test agent status changes
- Test queue functionality

## Troubleshooting

### Common Issues

1. **MongoDB Connection Errors**
   - Check connection string
   - Verify network access
   - Check authentication credentials

2. **Twilio API Errors**
   - Verify Account SID and Auth Token
   - Check webhook URLs
   - Verify phone number ownership

3. **WebSocket Connection Issues**
   - Check firewall settings
   - Verify WebSocket support
   - Check browser compatibility

### Logs
- Application logs: Check stdout/stderr
- MongoDB logs: Check MongoDB log files
- Web server logs: Check nginx/apache logs

## Maintenance

### Regular Tasks
- Monitor application performance
- Update dependencies regularly
- Backup database
- Review and rotate credentials
- Monitor security advisories

### Scaling Considerations
- Use load balancers for multiple instances
- Consider Redis for session storage
- Implement horizontal scaling for MongoDB
- Use CDN for static assets
