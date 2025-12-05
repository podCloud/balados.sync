/**
 * Global type definitions for window and application globals
 */

interface Window {
  /**
   * Global WebSocket manager instance (for debugging)
   * Provides connection control and message sending for dispatch events
   * @internal
   */
  __dispatchEventsManager?: {
    endpoint: string
    token: string | null
    state: 'disconnected' | 'connecting' | 'connected' | 'error'
    connect(): Promise<void>
    sendRecordPlay(feed: string, item: string): Promise<any>
  }

  /**
   * Phoenix LiveSocket instance
   * @internal
   */
  liveSocket?: any
}
