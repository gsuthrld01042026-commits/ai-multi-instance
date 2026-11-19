# TV Browser for Roku

A free web browser for Roku TVs, including Sharp Roku TVs.

Roku TVs can't show web pages themselves, because Roku OS has no web engine.
TV Browser gets around this:

- A small **server on your computer** runs a real Chrome-based browser in the background.
- The **TV Browser channel on your Roku** shows that browser's screen and turns
  your remote presses into clicks, scrolling and typing.

You get full, modern websites, including logins, search and forms. Your computer
needs to be on and on the same Wi-Fi/network as the TV while you browse.

## 1. Start the server on your computer (Windows, Mac or Linux)

1. Install [Node.js](https://nodejs.org) (the LTS version).
2. Open a terminal (Windows: **PowerShell**) in the `roku-browser/server` folder and run:
   ```
   npm run setup
   npm start
   ```
   `npm run setup` is only needed the first time. It downloads Chromium (about 150 MB).
3. The server prints the address to type on the TV, for example `192.168.1.20:8080`.
   If Windows asks whether to allow Node.js on private networks, click **Allow**.

Optional settings: `PORT=9000`, `HOME_URL=https://www.google.com`, `ZOOM=1.5`
(set them before `npm start`).

## 2. Install the channel on your Roku TV

Roku only lets you install your own channels in **developer mode**:

1. On the Roku remote, press: **Home ×3, Up ×2, Right, Left, Right, Left, Right**.
2. Write down the IP address shown, choose **Enable installer and restart**, accept
   the license, and set a password (the username is `rokudev`).
3. On your computer, open `http://<your-roku-ip>` in a web browser and sign in.
4. Click **Upload**, choose `roku-browser/tv-browser-roku.zip`, then click **Install with zip**.
5. TV Browser opens. Type the server address from step 1. It's remembered after that.

The channel then appears on your Home screen as **TV Browser**. A developer channel
stays installed until you install a different developer channel.

To rebuild the zip after changing the channel code, run `./build-channel.sh`.

## Using the remote

| Button | Action |
| --- | --- |
| Arrows | Move the pointer (hold to speed up). Pushing past the top or bottom edge scrolls the page |
| OK | Click. Clicking a text box opens the on-screen keyboard |
| Back | Previous page. On the first page, press Back twice to exit |
| ⏪ / ⏩ | Scroll up or down one screen |
| ▶❚❚ | Toggle a faster pointer |
| ↺ (Replay) | Reload |
| ✱ (Options) | Menu: go to an address or search, type text, Enter/Backspace/Tab, forward, home, zoom, change server |

Words typed in the address box are searched on DuckDuckGo.

## Notes and limits

- **Video and sound:** you see a fresh picture about every 2.5 seconds and after every
  press, so it works well for reading, searching and forms. It does not play
  video or audio smoothly. For YouTube, Netflix and similar sites, use their Roku channels.
- **Privacy:** the server only accepts `http`/`https` pages (it can't open files on
  your computer). But anyone on your home network who knows the address can control
  it while it runs, so stop it with **Ctrl+C** when you're done, and don't run it on
  public Wi-Fi.
- If the TV says it can't reach the server, check that the computer and TV are on
  the same network, that the server is running, and that your firewall allows the port.
