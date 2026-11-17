# MeetingAlarm

A macOS menu bar app that keeps an eye on your Google calendars and makes sure you never miss a meeting.

- **Menu bar list** of today's and tomorrow's meetings from any number of Google accounts, each with a Join button when a video link is found (Google Meet, Zoom, Teams, Webex, Whereby, Around, Chime, Slack huddles).
- **10 minutes before:** a translucent overlay in a screen corner with a live countdown. Corner, size and opacity are configurable.
- **2 minutes before:** a Join button appears on the overlay.
- **30 seconds before:** the whole screen (every display) is taken over until you click **Join** or **Dismiss**.

All three thresholds can be changed in Settings → Alerts. Only meetings with a video link trigger alerts. All-day, declined, out-of-office and focus-time events are ignored.

## Requirements

- macOS 15+
- Xcode 16+ (built with Xcode 27)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Choosing a calendar source

In Settings → Accounts you can use either or both:

- **Mac Calendar (easiest, no setup):** add your Google/work accounts in System Settings → Internet Accounts, then turn on *Use calendars from the Mac Calendar app* and grant calendar access. No Google Cloud project or OAuth client needed.
- **Direct Google accounts:** needs your own OAuth client, see below.

## Google setup (one-time, only for direct Google accounts)

The app talks to the Google Calendar API directly, so it needs your own OAuth client:

1. Go to [Google Cloud Console](https://console.cloud.google.com/), create a project (e.g. "MeetingAlarm").
2. **APIs & Services → Library**, then enable the **Google Calendar API**.
3. **APIs & Services → OAuth consent screen**: choose *External*, fill in the app name and your email. Under *Test users*, add every Google account you want to connect. Leaving it in *Testing* mode is fine for personal use.
   - Note: refresh tokens for apps in Testing mode expire after 7 days, so you will have to click **Reconnect** weekly. To avoid that, publish the app (*Publish app* on the consent screen). Unverified apps are fine for personal use; Google shows a warning screen you can click through.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**, application type **Desktop app**.
5. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` and paste in the client ID and secret. (For desktop apps the "secret" is not truly secret, but it is still kept out of git.)

## Build and run

```sh
make test    # unit tests
make run     # build Debug and launch
make build   # build only
```

`make gen` regenerates `MeetingAlarm.xcodeproj` from `project.yml` if you want to open it in Xcode.

Then click the calendar icon in the menu bar → **Settings… → Accounts → Add Google Account…**. Sign in in your browser and return to the app. Repeat for each account. Expand an account to choose which calendars are watched (calendars hidden in Google Calendar start disabled).

## Testing alerts without a real meeting

Debug builds have a row of buttons in the menu bar popover (**+11m**, **+2:10**, **+0:40**) that add fake meetings. You can also launch with:

```sh
open build/Build/Products/Debug/MeetingAlarm.app --args -debugMeetings 40,130,660
```

## Notes

- Refresh tokens live in the login Keychain. The build is ad-hoc signed, so after a rebuild macOS may ask once per account whether MeetingAlarm can access its keychain item. Choose **Always Allow**.
- Calendars refresh every 5 minutes, on wake from sleep and when the network comes back.
- Dismissing (or joining) a meeting is remembered across relaunches. If the meeting is moved to a new time it will alert again.
- The × on the overlay only hides the overlay; the full-screen alert still appears at 30 s.

## Layout

```
project.yml                 XcodeGen spec
Config/                     xcconfig (+ gitignored Secrets.xcconfig)
MeetingAlarm/Sources/
  App/                      @main, app delegate
  Auth/                     OAuth (PKCE + loopback), Keychain
  Calendar/                 Google API client, models, join-link extraction
  Core/                     MeetingStore, AlertPlanner (pure logic), AlertCoordinator, Prefs
  UI/                       Menu bar, overlay panel, full-screen takeover, settings
  Debug/                    Debug-only fake meetings
MeetingAlarm/Tests/         Swift Testing unit tests
```
