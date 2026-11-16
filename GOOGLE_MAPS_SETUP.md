# Google Maps Setup Guide

## Step 1: Get API Key from Google Cloud Console

1. **Go to Google Cloud Console**
   - Visit: https://console.cloud.google.com/

2. **Select or Create a Project**
   - Click the project dropdown at the top
   - Select your existing Firebase project: `abts-dca9c`
   - OR create a new project if needed

3. **Enable Required APIs**
   - In the left menu, go to: **APIs & Services** > **Library**
   - Search for and enable these APIs:
     - **Maps SDK for Android**
     - **Maps SDK for iOS**
   - Click "Enable" for each one

4. **Create API Key**
   - Go to: **APIs & Services** > **Credentials**
   - Click **+ CREATE CREDENTIALS** > **API Key**
   - Copy the API key (you'll need this!)
   - Example format: `AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

5. **Restrict the API Key (IMPORTANT for security)**
   - Click on your newly created API key to edit it
   - Under "Application restrictions":
     - For iOS: Choose "iOS apps" and add your bundle ID: `com.example.btsDeliveryApp`
     - For Android: Choose "Android apps" and add:
       - Package name: `com.example.bts_delivery_app`
       - SHA-1 certificate fingerprint (get this by running the command below)
   - Under "API restrictions":
     - Select "Restrict key"
     - Check: Maps SDK for Android, Maps SDK for iOS
   - Click **Save**

## Step 2: Get SHA-1 Certificate (for Android)

Run this command in your terminal:

```bash
# For debug key (development)
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# Look for the SHA-1 line in the output, it looks like:
# SHA1: 5E:8F:16:06:2E:A3:CD:2C:4A:0D:54:78:76:BA:A6:F3:8C:AB:F6:25
```

Copy the SHA-1 fingerprint and add it to your API key restrictions.

## Step 3: What to Do Next

Once you have your API key, tell me and I'll help you:
1. Add it to your iOS configuration
2. Add it to your Android configuration
3. Test the map functionality

## Need Help?

- **Billing**: Google Maps requires a billing account but has a generous free tier ($200 credit/month)
- **Bundle ID**: Found in `ios/Runner/Info.plist` (usually `com.example.btsDeliveryApp`)
- **Package Name**: Found in `android/app/build.gradle` (usually `com.example.bts_delivery_app`)

---

**IMPORTANT**: Do NOT commit your API key to GitHub! We'll add it to `.gitignore`.
