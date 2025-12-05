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

class WebSocketManager {
  constructor(endpoint, token) {
    this.endpoint = endpoint;
    this.token = token;
    this.ws = null;
    this.state = 'disconnected'; // disconnected, connecting, connected, error
    this.messageQueue = [];
    this.connectTimeout = null;
    this.responseHandlers = new Map();
    this.messageId = 0;
  }

  /**
   * Connect to WebSocket and authenticate
   * Returns a promise that resolves when authenticated
   */
  connect() {
    return new Promise((resolve, reject) => {
      if (this.state === 'connected') {
        resolve();
        return;
      }

      if (this.state === 'connecting') {
        // Already connecting, add resolver to queue
        this.pendingResolvers = this.pendingResolvers || [];
        this.pendingResolvers.push({ resolve, reject });
        return;
      }

      this.state = 'connecting';
      this.pendingResolvers = [{ resolve, reject }];

      try {
        this.ws = new WebSocket(this.endpoint);

        this.ws.onopen = () => {
          this._sendAuthMessage();
          // Timeout waiting for auth response
          this.connectTimeout = setTimeout(() => {
            this.state = 'error';
            this.ws.close();
            this._rejectPending('WebSocket connection timeout');
          }, 5000);
        };

        this.ws.onmessage = (event) => {
          this._handleMessage(event);
        };

        this.ws.onerror = (error) => {
          console.error('[DispatchEvents] WebSocket error:', error);
          this.state = 'error';
          this._rejectPending('WebSocket error');
        };

        this.ws.onclose = () => {
          this.state = 'disconnected';
          clearTimeout(this.connectTimeout);
        };
      } catch (error) {
        console.error('[DispatchEvents] Failed to create WebSocket:', error);
        this.state = 'error';
        reject(error);
      }
    });
  }

  /**
   * Send a record_play event
   * Returns promise that resolves when event is confirmed
   */
  sendRecordPlay(feed, item) {
    return new Promise((resolve, reject) => {
      const messageId = ++this.messageId;

      const timeout = setTimeout(() => {
        this.responseHandlers.delete(messageId);
        reject(new Error('record_play timeout'));
      }, 5000);

      // Store handler with timeout for cleanup
      this.responseHandlers.set(messageId, { resolve, reject, timeout });

      const message = {
        id: messageId,
        type: 'record_play',
        feed,
        item,
        position: 0,
        played: false
      };

      if (this.state === 'connected' && this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify(message));
      } else {
        // Queue message if not connected (max 50 messages to prevent unbounded growth)
        if (this.messageQueue.length >= 50) {
          const dropped = this.messageQueue.shift();
          clearTimeout(dropped.timeout);
          console.warn('[DispatchEvents] Message queue full, dropping oldest message');
        }
        this.messageQueue.push({ message, messageId, timeout, resolve, reject });

        // Try to reconnect and send
        this.connect().catch(() => {
          clearTimeout(timeout);
          this.responseHandlers.delete(messageId);
          reject(new Error('Failed to connect to WebSocket'));
        });
      }
    });
  }

  _sendAuthMessage() {
    if (!this.token) {
      console.warn('[DispatchEvents] No token available, cannot authenticate');
      this.state = 'error';
      this._rejectPending('No authentication token');
      return;
    }

    const authMessage = {
      type: 'auth',
      token: this.token
    };

    try {
      this.ws.send(JSON.stringify(authMessage));
    } catch (error) {
      console.error('[DispatchEvents] Failed to send auth message:', error);
      this.state = 'error';
      this._rejectPending('Failed to send auth');
    }
  }

  _handleMessage(event) {
    try {
      const data = JSON.parse(event.data);

      // Handle auth response
      if (data.type === 'auth' || (data.status === 'ok' && data.data?.user_id !== undefined)) {
        clearTimeout(this.connectTimeout);

        if (data.status === 'ok') {
          this.state = 'connected';
          this._resolvePending();
          this._processMessageQueue();
        } else {
          this.state = 'error';
          this._rejectPending(data.error?.message || 'Authentication failed');
        }
        return;
      }

      // Handle record_play response
      if (data.id && this.responseHandlers.has(data.id)) {
        const { resolve, reject, timeout } = this.responseHandlers.get(data.id);
        clearTimeout(timeout);
        this.responseHandlers.delete(data.id);

        if (data.status === 'ok') {
          resolve(data);
        } else {
          reject(new Error(data.error?.message || 'record_play failed'));
        }
      }
    } catch (error) {
      console.error('[DispatchEvents] Error handling WebSocket message:', error);
    }
  }

  _processMessageQueue() {
    while (this.messageQueue.length > 0) {
      const { message, messageId, timeout } = this.messageQueue.shift();

      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify(message));
      } else {
        // Re-queue if connection lost
        this.messageQueue.unshift({ message, messageId, timeout });
        break;
      }
    }
  }

  _resolvePending() {
    if (this.pendingResolvers) {
      this.pendingResolvers.forEach(({ resolve }) => resolve());
      this.pendingResolvers = [];
    }
  }

  _rejectPending(reason) {
    if (this.pendingResolvers) {
      this.pendingResolvers.forEach(({ reject }) => reject(new Error(reason)));
      this.pendingResolvers = [];
    }
  }
}

class DispatchEventHandler {
  constructor(wsManager) {
    this.wsManager = wsManager;
    this.setupListeners();
  }

  setupListeners() {
    // Find all elements with data-dispatch-event attribute
    document.querySelectorAll('[data-dispatch-event]').forEach((element) => {
      element.addEventListener('click', (e) => this.handleClick(e));
    });

    // Also listen for dynamically added elements
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === 1) { // Element node
            if (node.hasAttribute('data-dispatch-event')) {
              node.addEventListener('click', (e) => this.handleClick(e));
            }
            node.querySelectorAll('[data-dispatch-event]').forEach((el) => {
              el.addEventListener('click', (e) => this.handleClick(e));
            });
          }
        });
      });
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true
    });
  }

  handleClick(event) {
    const link = event.currentTarget;
    const eventType = link.getAttribute('data-dispatch-event');

    // Only handle 'play' events for now
    if (eventType !== 'play') {
      return;
    }

    const feed = link.getAttribute('data-feed');
    const item = link.getAttribute('data-item');
    const href = link.href;

    // Always prevent default to handle it ourselves
    event.preventDefault();

    // If no WebSocket token, redirect directly
    if (!this.wsManager.token) {
      window.location.href = href;
      return;
    }

    // Try to send event via WebSocket, with timeout fallback
    this.wsManager.connect()
      .then(() => this.wsManager.sendRecordPlay(feed, item))
      .then(() => {
        // Success: redirect after event recorded
        window.location.href = href;
      })
      .catch((error) => {
        console.warn('[DispatchEvents] Failed to record play event, redirecting anyway:', error);
        // Timeout or error: redirect anyway (graceful degradation)
        window.location.href = href;
      });
  }
}

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  // Get configuration from meta tags
  const wsEndpoint = document.querySelector('meta[name="ws-endpoint"]')?.content;
  const wsToken = document.querySelector('meta[name="ws-token"]')?.content;

  // Only initialize if we have an endpoint
  if (!wsEndpoint) {
    console.warn('[DispatchEvents] No WebSocket endpoint configured');
    return;
  }

  // Create WebSocket manager (token may be null for non-authenticated users)
  const wsManager = new WebSocketManager(wsEndpoint, wsToken);

  // Create dispatch event handler
  new DispatchEventHandler(wsManager);

  // Make wsManager available globally for debugging if needed
  window.__dispatchEventsManager = wsManager;
});
