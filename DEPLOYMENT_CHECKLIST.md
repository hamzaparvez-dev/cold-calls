# Twilio Dialer - Render Deployment Checklist

## Pre-Deployment Checklist

### ✅ 1. Code Preparation
- [x] Updated Gemfile with production dependencies
- [x] Created production-ready application file (client-acd-production.rb)
- [x] Updated config.ru to use production file
- [x] Created render.yaml configuration
- [x] Created deployment documentation

### ✅ 2. Environment Variables Required
You need to set these in Render dashboard:

**Twilio Configuration:**
- [ ] `twilio_account_sid` - Your Twilio Account SID
- [ ] `twilio_account_token` - Your Twilio Auth Token  
- [ ] `twilio_app_id` - Your Twilio TwiML App SID
- [ ] `twilio_caller_id` - Your Twilio phone number (+1234567890)
- [ ] `twilio_queue_name` - Queue name (e.g., "CustomerService")
- [ ] `twilio_dqueue_url` - Will be https://your-app.onrender.com/voice

**Database Configuration:**
- [ ] `MONGODB_URI` - MongoDB Atlas connection string

**Application Configuration:**
- [ ] `RACK_ENV` - Set to "production"
- [ ] `PORT` - Set to "10000" (Render default)
- [ ] `LOG_LEVEL` - Set to "INFO"
- [ ] `anycallerid` - Set to "none"

## Step-by-Step Deployment Process

### Step 1: Prepare Your Repository
```bash
# Initialize git repository
git init
git add .
git commit -m "Initial commit for Render deployment"

# Push to GitHub (replace with your repository)
git remote add origin https://github.com/yourusername/twilio-dialer.git
git push -u origin main
```

### Step 2: Set Up MongoDB Atlas
1. Go to https://cloud.mongodb.com
2. Create a free cluster (M0 Sandbox)
3. Create database user with username/password
4. Whitelist IP address `0.0.0.0/0` for Render access
5. Get connection string (mongodb+srv://...)

### Step 3: Deploy on Render
1. Go to https://dashboard.render.com
2. Click "New +" → "Web Service"
3. Connect your GitHub repository
4. Render will auto-detect the render.yaml file
5. Configure environment variables (see list above)

### Step 4: Configure Twilio Webhooks
After deployment, update your Twilio phone number:
- Voice URL: `https://your-app-name.onrender.com/voice`
- Status Callback: `https://your-app-name.onrender.com/handledialcallstatus`

### Step 5: Test Deployment
- [ ] Visit your app URL
- [ ] Test incoming calls
- [ ] Test click-to-dial functionality
- [ ] Check Render logs for errors

## Quick Start Commands

### Get Twilio Values:
```bash
# Account SID & Auth Token
# Go to: https://twilio.com/user/account

# App ID (TwiML App)
# Go to: https://console.twilio.com/us1/develop/twiml-apps

# Phone Number
# Go to: https://console.twilio.com/us1/develop/phone-numbers/manage/incoming
```

### Test Locally (Optional):
```bash
# Create .env file with your values
cp .env.example .env
# Edit .env with your credentials

# Run test script
ruby test_app.rb

# Start application
bundle exec ruby client-acd-production.rb
```

## Troubleshooting

### Common Issues:
1. **Build Failures**: Check Ruby version and gem compatibility
2. **Database Errors**: Verify MongoDB URI and IP whitelist
3. **Twilio Errors**: Check Account SID, Auth Token, and webhook URLs
4. **WebSocket Issues**: Ensure HTTPS is properly configured

### Render-Specific:
- Free tier services sleep after 15 minutes of inactivity
- Cold starts take 30-60 seconds
- Upgrade to paid plan for always-on service

## Production Tips:
1. Use custom domain for professional webhooks
2. Set up monitoring and alerts
3. Regular MongoDB backups
4. SSL certificate management
5. Performance monitoring

## Support Resources:
- Render Docs: https://render.com/docs
- Twilio Docs: https://www.twilio.com/docs
- MongoDB Atlas: https://docs.atlas.mongodb.com
