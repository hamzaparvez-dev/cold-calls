# Environment Variables Configuration Guide

## Required Environment Variables

Create a `.env` file in the lightning-dialer directory with the following variables:

### Twilio Configuration
```bash
# Get these values from https://twilio.com/user/account
twilio_account_sid=your_twilio_account_sid_here
twilio_account_token=your_twilio_auth_token_here
twilio_app_id=your_twilio_app_id_here
twilio_caller_id=your_twilio_phone_number_here
twilio_queue_name=CustomerService
twilio_dqueue_url=https://your-app-domain.com/voice
```

### MongoDB Configuration
```bash
# For local development
MONGODB_URI=mongodb://localhost:27017/twilio_dialer

# For production (MongoDB Atlas example)
# MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/twilio_dialer
```

### Optional Configuration
```bash
# Set to "inline" if you want agents to set their own caller ID
# Note: Requires Twilio account provisioning for any caller ID feature
anycallerid=none

# Production Environment Settings
RACK_ENV=production
PORT=5000

# Security Settings
SECRET_KEY=your_secret_key_here_for_session_management
```

## How to Get Twilio Values

1. **Account SID & Auth Token**: 
   - Go to https://twilio.com/user/account
   - Find "Account SID" and "Auth Token" in the Account Info section

2. **App ID**:
   - Go to Twilio Console > Dev Tools > TwiML Apps
   - Create a new TwiML App or use existing one
   - Set Voice URL to: `https://your-domain.com/dial`
   - Copy the App SID

3. **Caller ID**:
   - Use a phone number from your Twilio account
   - Go to Phone Numbers > Manage > Active numbers
   - Copy any active phone number

4. **Queue Name**:
   - This is user-defined (e.g., "CustomerService", "Sales", "Support")

5. **DQueue URL**:
   - This should be your deployed app URL + `/voice`
   - Example: `https://your-app.herokuapp.com/voice`

## Production Deployment Notes

- Never commit `.env` files to version control
- Use environment variables in production (Heroku, AWS, etc.)
- Ensure MongoDB is accessible from your production environment
- Set up proper SSL certificates for HTTPS
- Configure firewall rules for MongoDB access
