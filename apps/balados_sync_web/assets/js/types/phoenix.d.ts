/**
 * Type definitions for Phoenix and Phoenix LiveView
 * These are custom definitions since Phoenix doesn't provide official TS types
 */

declare module 'phoenix' {
  export class Socket {
    constructor(endPoint: string, opts?: any)
    connect(): void
    disconnect(callback?: () => void, code?: number, reason?: string): void
    channel(topic: string, chanParams?: object): Channel
    on(event: string, callback: (response: any) => void): void
    off(event: string): void
    push(topic: string, event: string, payload: object, timeout?: number): Push
  }

  export class Channel {
    join(timeout?: number): Push
    leave(timeout?: number): Push
    on(event: string, callback: (response: any) => void): void
    off(event: string): void
    push(event: string, payload: object, timeout?: number): Push
  }

  export class Push {
    receive(status: string, callback: (response: any) => void): Push
  }
}

declare module 'phoenix_live_view' {
  import { Socket } from 'phoenix'

  export class LiveSocket {
    constructor(
      url: string,
      Socket: typeof import('phoenix').Socket,
      opts?: LiveSocketOptions
    )
    connect(): void
    disconnect(callback?: () => void): void
    enableDebug(): void
    enableLatencySim(upperBoundMs: number): void
    disableLatencySim(): void
  }

  export interface LiveSocketOptions {
    params?: object | (() => object)
    longPollFallbackMs?: number
    debug?: boolean
    hooks?: Record<string, ViewHook>
    dom?: {
      onBeforeElUpdated?: (from: HTMLElement, to: HTMLElement) => boolean
    }
  }

  export interface ViewHook {
    mounted?(): void
    beforeUpdate?(): void
    updated?(): void
    destroyed?(): void
    disconnected?(): void
    reconnected?(): void
  }
}
