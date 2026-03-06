# Sparkle Auto-Update Setup

LockOut uses [Sparkle 2.6.0](https://sparkle-project.org) for auto-updates.

## Setup Steps

1. **Generate EdDSA keys:**
   ```
   ./Packages/Sparkle/bin/generate_keys
   ```
   This prints a public key. Copy it.

2. **Configure `Config.xcconfig`:**
   ```
   SPARKLE_FEED_URL = https://your-domain.com/appcast.xml
   SPARKLE_ED_KEY = <your-public-EdDSA-key>
   ```

3. **Host an appcast XML** at the URL above. Example:
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
     <channel>
       <title>LockOut</title>
       <item>
         <title>1.1.0</title>
         <sparkle:version>2</sparkle:version>
         <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
         <pubDate>Mon, 01 Jan 2026 00:00:00 +0000</pubDate>
         <enclosure url="https://your-domain.com/LockOut-1.1.0.dmg"
                    sparkle:edSignature="<signature>"
                    length="12345678"
                    type="application/octet-stream"/>
       </item>
     </channel>
   </rss>
   ```

4. **Sign each release DMG:**
   ```
   ./Packages/Sparkle/bin/sign_update dist/LockOut.dmg
   ```
   Paste the signature into the appcast `sparkle:edSignature`.

5. **Upload** the DMG and appcast to your hosting.

## Testing

- Build a debug version with a lower `CURRENT_PROJECT_VERSION`
- Point `SPARKLE_FEED_URL` to a local server
- Launch the app; it should detect the update
