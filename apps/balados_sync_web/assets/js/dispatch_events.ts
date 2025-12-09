/**
 * Dispatch Events System
 *
 * Handles WebSocket communication for tracking play events
 * Uses data-dispatch-event attributes on links for progressive enhancement
 *
 * Usage:
 * <a href="https://example.com/episode.mp3"
 *    data-dispatch-event="play"
 *    data-feed="base64_encoded_feed_url"
 *    data-item="base64_encoded_item_id">
 *   Play Episode
 * </a>
 */

console.log('[DispatchEvents] Module loading...')

/**
 * Configuration constants
 */
const CONFIG = {
  CONNECT_TIMEOUT_MS: 5000,
  RECORD_PLAY_TIMEOUT_MS: 5000,
  MAX_QUEUE_SIZE: 50,
}

/**
 * Response handler with cleanup callback
 */
interface ResponseHandler {
  resolve: (value: any) => void
  reject: (reason?: any) => void
  timeout: number
}

/**
 * Queued message item
 */
interface QueuedMessage {
  message: Record<string, any>
  messageId: number
  timeout: number
  resolve: (value: any) => void
  reject: (reason?: any) => void
}

/**
 * Manages WebSocket connection and message dispatch
 */
class WebSocketManager {
  endpoint: string
  token: string | null
  private ws: WebSocket | null = null
  state: 'disconnected' | 'connecting' | 'connected' | 'error' = 'disconnected'
  private messageQueue: QueuedMessage[] = []
  private connectTimeout: number | null = null
  private responseHandlers: Map<number, ResponseHandler> = new Map()
  private messageId: number = 0
  private pendingResolvers: Array<{ resolve: () => void; reject: (reason: any) => void }> = []

  constructor(endpoint: string, token: string | null) {
    this.endpoint = endpoint
    this.token = token
  }

  /**
   * Connect to WebSocket and authenticate
   * Returns a promise that resolves when authenticated
   */
  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.state === 'connected') {
        resolve()
        return
      }

      if (this.state === 'connecting') {
        // Already connecting, add resolver to queue
        this.pendingResolvers.push({ resolve, reject })
        return
      }

      this.state = 'connecting'
      this.pendingResolvers = [{ resolve, reject }]

      try {
        this.ws = new WebSocket(this.endpoint)

        this.ws.onopen = () => {
          this._sendAuthMessage()
          // Timeout waiting for auth response
          this.connectTimeout = window.setTimeout(() => {
            this.state = 'error'
            this.ws?.close()
            this._rejectPending('WebSocket connection timeout')
          }, CONFIG.CONNECT_TIMEOUT_MS)
        }

        this.ws.onmessage = (event: MessageEvent) => {
          this._handleMessage(event)
        }

        this.ws.onerror = (error: Event) => {
          console.error('[DispatchEvents] WebSocket error:', error)
          this.state = 'error'
          this._rejectPending('WebSocket error')
        }

        this.ws.onclose = () => {
          this.state = 'disconnected'
          if (this.connectTimeout !== null) {
            clearTimeout(this.connectTimeout)
          }
          // Clean up all pending handlers and reject promises
          this._cleanupOnClose()
        }
      } catch (error) {
        console.error('[DispatchEvents] Failed to create WebSocket:', error)
        this.state = 'error'
        reject(error)
      }
    })
  }

  /**
   * Send a record_play event
   * Returns promise that resolves when event is confirmed
   */
  sendRecordPlay(feed: string, item: string, privacy?: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const messageId = ++this.messageId

      const timeout = window.setTimeout(() => {
        this.responseHandlers.delete(messageId)
        reject(new Error('record_play timeout'))
      }, CONFIG.RECORD_PLAY_TIMEOUT_MS)

      // Store handler with timeout for cleanup
      this.responseHandlers.set(messageId, { resolve, reject, timeout })

      const message: Record<string, any> = {
        opid: messageId,
        type: 'record_play',
        feed,
        item,
        position: 0,
        played: true,
      }

      // Only include privacy if provided
      if (privacy) {
        message.privacy = privacy
      }

      if (this.state === 'connected' && this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify(message))
      } else {
        // Queue message if not connected (max 50 messages to prevent unbounded growth)
        if (this.messageQueue.length >= CONFIG.MAX_QUEUE_SIZE) {
          const dropped = this.messageQueue.shift()
          if (dropped) {
            clearTimeout(dropped.timeout)
            console.warn('[DispatchEvents] Message queue full, dropping oldest message')
          }
        }
        this.messageQueue.push({ message, messageId, timeout, resolve, reject })

        // Try to reconnect and send
        this.connect().catch(() => {
          clearTimeout(timeout)
          this.responseHandlers.delete(messageId)
          reject(new Error('Failed to connect to WebSocket'))
        })
      }
    })
  }

  private _sendAuthMessage(): void {
    if (!this.token) {
      console.warn('[DispatchEvents] No token available, cannot authenticate')
      this.state = 'error'
      this._rejectPending('No authentication token')
      return
    }

    const authMessage = {
      type: 'auth',
      token: this.token,
    }

    try {
      this.ws?.send(JSON.stringify(authMessage))
    } catch (error) {
      console.error('[DispatchEvents] Failed to send auth message:', error)
      this.state = 'error'
      this._rejectPending('Failed to send auth')
    }
  }

  private _handleMessage(event: MessageEvent): void {
    try {
      const data = JSON.parse(event.data) as Record<string, any>

      // Handle auth response
      if (data.type === 'auth' || (data.status === 'ok' && data.data?.user_id !== undefined)) {
        if (this.connectTimeout !== null) {
          clearTimeout(this.connectTimeout)
        }

        if (data.status === 'ok') {
          this.state = 'connected'
          this._resolvePending()
          this._processMessageQueue()
        } else {
          this.state = 'error'
          this._rejectPending(data.error?.message || 'Authentication failed')
        }
        return
      }

      // Handle record_play response
      if (data.opid && this.responseHandlers.has(data.opid)) {
        const handler = this.responseHandlers.get(data.opid)
        if (!handler) return

        const { resolve, reject, timeout } = handler
        clearTimeout(timeout)
        this.responseHandlers.delete(data.opid)

        if (data.status === 'ok') {
          resolve(data)
        } else {
          reject(new Error(data.error?.message || 'record_play failed'))
        }
      }
    } catch (error) {
      console.error('[DispatchEvents] Error handling WebSocket message:', error)
    }
  }

  private _processMessageQueue(): void {
    while (this.messageQueue.length > 0) {
      const queuedItem = this.messageQueue[0]
      const { message, messageId, timeout, resolve, reject } = queuedItem

      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        // Register handler before sending to ensure cleanup works
        this.responseHandlers.set(messageId, { resolve, reject, timeout })
        this.messageQueue.shift()

        try {
          this.ws.send(JSON.stringify(message))
        } catch (error) {
          // If send fails, put message back and stop processing
          this.responseHandlers.delete(messageId)
          this.messageQueue.unshift(queuedItem)
          break
        }
      } else {
        // Connection not ready, stop processing
        break
      }
    }
  }

  private _resolvePending(): void {
    if (this.pendingResolvers.length > 0) {
      this.pendingResolvers.forEach(({ resolve }) => resolve())
      this.pendingResolvers = []
    }
  }

  private _rejectPending(reason: string): void {
    if (this.pendingResolvers.length > 0) {
      this.pendingResolvers.forEach(({ reject }) => reject(new Error(reason)))
      this.pendingResolvers = []
    }
  }

  private _cleanupOnClose(): void {
    // Clean up all response handlers and clear their timeouts
    this.responseHandlers.forEach(({ timeout }) => {
      clearTimeout(timeout)
    })
    this.responseHandlers.clear()

    // Clean up message queue timeouts
    this.messageQueue.forEach(({ timeout }) => {
      clearTimeout(timeout)
    })
  }
}

/**
 * Handles dispatch events on elements with data-dispatch-event attributes
 */
class DispatchEventHandler {
  private wsManager: WebSocketManager

  constructor(wsManager: WebSocketManager) {
    this.wsManager = wsManager
    this.setupListeners()
  }

  private setupListeners(): void {
    // Use event delegation on document.body to handle all clicks
    // This avoids duplicate listeners and handles dynamically added elements
    document.body.addEventListener(
      'click',
      (event: Event) => {
        const target = event.target as HTMLElement
        // Check if the clicked element or any parent has data-dispatch-event
        const link = target.closest('[data-dispatch-event]')
        if (link instanceof HTMLElement) {
          this.handleClick(event as MouseEvent, link)
        }
      },
      true
    ) // Use capture phase for reliability
  }

  private handleClick(event: MouseEvent, link: HTMLElement): void {
    const eventType = link.getAttribute('data-dispatch-event')

    // Only handle 'play' events for now
    if (eventType !== 'play') {
      return
    }

    const feed = link.getAttribute('data-feed')
    const item = link.getAttribute('data-item')

    if (!feed || !item) {
      console.warn('[DispatchEvents] Missing feed or item attributes')
      return
    }

    // Import dynamically to avoid circular dependencies
    import('./privacy_manager').then(({ privacyManager }) => {
      this.handlePlayLinkClick(event, link, privacyManager, feed, item)
    })
  }

  /**
   * Handle play link click
   * Privacy controls whether we record the event, NOT whether the link opens
   * - If privacy is cached: send recordPlay if not private, allow normal link
   * - If privacy is unknown: prevent default, show modal, send recordPlay if not private, then open link manually
   */
  private async handlePlayLinkClick(
    event: MouseEvent,
    link: HTMLElement,
    privacyManager: any,
    feed: string,
    item: string
  ): Promise<void> {
    // Check if privacy is cached
    const cachedPrivacy = privacyManager.privacyCache?.get(feed) || null

    if (cachedPrivacy !== null) {
      // Privacy is known - send recordPlay if not private, then allow normal link behavior
      console.log('[DispatchEvents] Privacy cached as', cachedPrivacy)

      if (cachedPrivacy !== 'private' && this.wsManager.token) {
        // Send recordPlay async (don't block the link)
        this.sendPlayEventAsync(feed, item, cachedPrivacy)
      }

      // Always let the link open normally
      return
    }

    // Privacy is unknown - need to show modal before we can decide about recordPlay
    console.log('[DispatchEvents] Privacy unknown, showing modal')
    event.preventDefault()

    const originalText = link.textContent || ''
    const originalOpacity = (link as any).style.opacity || '1'
    const href = (link as HTMLAnchorElement).href

    try {
      // Show loading state
      link.style.opacity = '0.5'
      link.textContent = 'Checking privacy...'

      // Request privacy choice (shows modal)
      const privacy = await privacyManager.ensurePrivacy(feed, 'play')

      console.log('[DispatchEvents] Privacy choice result:', privacy)
      link.textContent = 'Opening...'

      // Send recordPlay if privacy is not private
      if (privacy !== 'private' && this.wsManager.token) {
        try {
          await this.wsManager.connect()
          await this.wsManager.sendRecordPlay(feed, item, privacy)
          console.log('[DispatchEvents] Play event sent successfully')
        } catch (err) {
          console.error('[DispatchEvents] Failed to send play event:', err)
          // Still open the link even if event sending failed
        }
      }

      // Always open the link (whether user chose private, public, anonymous, or cancelled)
      window.open(href, '_blank')
    } catch (error) {
      console.error('[DispatchEvents] Error during play link handling:', error)
      link.style.opacity = originalOpacity
      link.textContent = originalText
    }
  }

  /**
   * Send play event asynchronously without blocking
   */
  private sendPlayEventAsync(feed: string, item: string, privacy: string): void {
    if (this.wsManager.token) {
      this.wsManager.connect()
        .then(() => this.wsManager.sendRecordPlay(feed, item, privacy))
        .catch((err) => {
          console.error('[DispatchEvents] Failed to send play event:', err)
        })
    }
  }
}

// Initialize function
const initializeDispatchEvents = () => {
  console.log('[DispatchEvents] Initializing dispatch events system')

  // Get configuration from meta tags
  const wsEndpointElement = document.querySelector<HTMLMetaElement>('meta[name="ws-endpoint"]')
  const wsTokenElement = document.querySelector<HTMLMetaElement>('meta[name="ws-token"]')

  const wsEndpoint = wsEndpointElement?.content
  const wsToken = wsTokenElement?.content

  console.log('[DispatchEvents] WS Endpoint:', wsEndpoint)
  console.log('[DispatchEvents] WS Token:', wsToken ? '(present)' : '(not set)')

  // Only initialize if we have an endpoint
  if (!wsEndpoint) {
    console.warn('[DispatchEvents] No WebSocket endpoint configured')
    return
  }

  // Create WebSocket manager (token may be null for non-authenticated users)
  const wsManager = new WebSocketManager(wsEndpoint, wsToken || null)

  // Create dispatch event handler
  new DispatchEventHandler(wsManager)

  // Make wsManager available globally for debugging if needed
  window.__dispatchEventsManager = wsManager

  console.log('[DispatchEvents] Initialization complete')
}

// Handle both DOMContentLoaded and already loaded
if (document.readyState === 'loading') {
  console.log('[DispatchEvents] DOM still loading, waiting for DOMContentLoaded')
  document.addEventListener('DOMContentLoaded', initializeDispatchEvents)
} else {
  console.log('[DispatchEvents] DOM already loaded, initializing immediately')
  initializeDispatchEvents()
}
