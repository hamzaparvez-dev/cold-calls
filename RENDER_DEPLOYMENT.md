# Render.com deployment guide for Twilio Dialer

## Prerequisites

1. **Render Account**: Sign up at https://render.com
2. **GitHub Repository**: Push your code to GitHub
3. **Twilio Account**: With phone number and credentials
4. **MongoDB Atlas**: Free cluster setup

## Step 1: Prepare Your Repository

1. **Push your code to GitHub**:
   ```bash
   git init
   git add .
   git commit -m "Initial commit for Render deployment"
   git branch -M main
   git remote add origin https://github.com/yourusername/your-repo-name.git
   git push -u origin main
   ```

## Step 2: Create MongoDB Database

1. **Go to MongoDB Atlas**: https://cloud.mongodb.com
2. **Create a free cluster** (M0 Sandbox)
3. **Create a database user**:
   - Username: `twilio-dialer-user`
   - Password: Generate a strong password
4. **Whitelist IP addresses**: Add `0.0.0.0/0` for Render access
5. **Get connection string**: Copy the MongoDB URI

## Step 3: Deploy on Render

### Option A: Using Render Dashboard

1. **Go to Render Dashboard**: https://dashboard.render.com
2. **Click "New +"** → **"Web Service"**
3. **Connect your GitHub repository**
4. **Configure the service**:
   - **Name**: `twilio-dialer`
   - **Environment**: `Ruby`
   - **Build Command**: `bundle install`
   - **Start Command**: `bundle exec puma -p $PORT -e production`
   - **Plan**: `Starter` (Free)

### Option B: Using render.yaml (Recommended)

1. **Use the render.yaml file** I created in your project
2. **Deploy directly from GitHub**:
   - Connect your repository
   - Render will automatically detect the render.yaml file
   - Follow the configuration

## Step 4: Set Environment Variables

In your Render service dashboard, add these environment variables:

### Required Variables:
```
RACK_ENV=production
PORT=10000
LOG_LEVEL=INFO
twilio_account_sid=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
twilio_account_token=your_auth_token_here
twilio_app_id=APxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
twilio_caller_id=+1234567890
twilio_queue_name=CustomerService
twilio_dqueue_url=https://your-app-name.onrender.com/voice
MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/twilio_dialer
anycallerid=none
```

### How to Get Twilio Values:

1. **Account SID & Auth Token**: 
   - Go to https://twilio.com/user/account
   - Copy from Account Info section

2. **App ID**:
   - Go to Twilio Console > Dev Tools > TwiML Apps
   - Create new app or use existing
   - Copy the App SID

3. **Caller ID**:
   - Use any phone number from your Twilio account
   - Format: `+1234567890`

4. **DQueue URL**:
   - This will be: `https://your-app-name.onrender.com/voice`
   - Replace `your-app-name` with your actual Render app name

## Step 5: Configure Twilio Webhooks

After deployment, update your Twilio configuration:

### Phone Number Webhooks:
1. **Go to Twilio Console** → **Phone Numbers** → **Manage** → **Active numbers**
2. **Click your phone number**
3. **Set webhooks**:
   - **Voice URL**: `https://your-app-name.onrender.com/voice`
   - **HTTP Method**: `POST`
   - **Status Callback URL**: `https://your-app-name.onrender.com/handledialcallstatus`

### TwiML App Configuration:
1. **Go to Twilio Console** → **Dev Tools** → **TwiML Apps**
2. **Click your app**
3. **Set webhooks**:
   - **Voice URL**: `https://your-app-name.onrender.com/dial`
   - **HTTP Method**: `POST`
   - **Status Callback URL**: `https://your-app-name.onrender.com/handledialcallstatus`

## Step 6: Test Your Deployment

1. **Check Render logs**: Go to your service → Logs tab
2. **Test the application**: Visit `https://your-app-name.onrender.com`
3. **Test incoming calls**: Call your Twilio phone number
4. **Test click-to-dial**: Use the web interface

## Troubleshooting

### Common Issues:

1. **Build Failures**:
   - Check Ruby version compatibility
   - Ensure all gems are properly specified
   - Check build logs in Render dashboard

2. **Database Connection Issues**:
   - Verify MongoDB URI format
   - Check IP whitelist in MongoDB Atlas
   - Ensure database user has proper permissions

3. **Twilio Webhook Issues**:
   - Verify webhook URLs are accessible
   - Check HTTPS certificate validity
   - Test webhook endpoints manually

4. **Application Crashes**:
   - Check environment variables are set
   - Review application logs
   - Verify all required services are running

### Render-Specific Tips:

1. **Free Tier Limitations**:
   - Services sleep after 15 minutes of inactivity
   - Cold starts may take 30-60 seconds
   - Upgrade to paid plan for always-on service

2. **Environment Variables**:
   - Use Render's environment variable interface
   - Mark sensitive variables as "Sync" = false
   - Restart service after changing environment variables

3. **Logs and Monitoring**:
   - Use Render's built-in logging
   - Set up external monitoring for production use
   - Monitor service health and performance

## Production Considerations

1. **Upgrade to Paid Plan**: For always-on service
2. **Set up Custom Domain**: For professional webhooks
3. **Configure SSL**: Ensure HTTPS for all webhooks
4. **Monitor Performance**: Set up alerts and monitoring
5. **Backup Strategy**: Regular MongoDB backups
6. **Security**: Review and update security settings

## Support

- **Render Documentation**: https://render.com/docs
- **Twilio Documentation**: https://www.twilio.com/docs
- **MongoDB Atlas**: https://docs.atlas.mongodb.com

Your Twilio Dialer should now be successfully deployed on Render!
