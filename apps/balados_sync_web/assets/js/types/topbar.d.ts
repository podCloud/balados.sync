/**
 * Type definitions for topbar.js
 * https://buunguyen.github.io/topbar/
 */

declare module '../vendor/topbar' {
  export interface TopbarConfig {
    autoRun?: boolean
    barColors?: { [key: number]: string }
    shadowColor?: string
    barThickness?: number
    barCSS?: string
    shadowCSS?: string
  }

  interface Topbar {
    config(config: TopbarConfig): void
    show(delay?: number): void
    hide(delay?: number): void
    resume(): void
    pause(): void
  }

  const topbar: Topbar
  export default topbar
}
