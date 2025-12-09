// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.ts"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
// @ts-ignore - topbar doesn't have TypeScript definitions
import topbar from "../vendor/topbar"

const csrfTokenElement = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")
const csrfToken = csrfTokenElement?.getAttribute("content") || ""

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", (_info: Event) => topbar.show(300))
window.addEventListener("phx:page-loading-stop", (_info: Event) => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Subscription management enhancements
import "./subscriptions.ts"

// WebSocket dispatch events for play tracking
import "./dispatch_events.ts"

// Mark as played handler for episodes
import "./mark_played"

// Modal management for login and subscription forms
import "./modals"

// Privacy management for subscriptions and plays
import { privacyManager } from "./privacy_manager"

// Subscribe flow with privacy checks
import "./subscribe_flow"

// Privacy manager page (inline edit mode)
import "./privacy-manager-page"

// Privacy badge on feed page
import "./privacy_badge"

// Episode sorting and popularity display
import "./episode_sorter"
