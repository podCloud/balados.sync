/**
 * Toast Notification System
 * Displays temporary notifications with auto-dismiss functionality
 */

interface Toast {
  id: string
  message: string
  type: 'info' | 'success' | 'error' | 'warning'
  duration?: number
}

class ToastManager {
  private toasts: Toast[] = []
  private container: HTMLDivElement | null = null
  private readonly maxVisible = 3
  private readonly defaultDuration = 5000 // 5 seconds

  constructor() {
    this.initializeContainer()
  }

  private initializeContainer(): void {
    // Create toast container if it doesn't exist
    let container = document.getElementById('toast-container') as HTMLDivElement
    if (!container) {
      container = document.createElement('div')
      container.id = 'toast-container'
      container.className = 'fixed top-4 left-4 z-50 space-y-2 max-w-sm pointer-events-none'
      document.body.appendChild(container)
    }
    this.container = container
  }

  /**
   * Show a toast notification
   */
  show(message: string, type: 'info' | 'success' | 'error' | 'warning' = 'info', duration?: number): void {
    const id = `toast-${Date.now()}-${Math.random()}`
    const toast: Toast = {
      id,
      message,
      type,
      duration: duration || this.defaultDuration
    }

    this.toasts.push(toast)
    this.render()

    // Auto-dismiss after duration
    if (toast.duration) {
      setTimeout(() => this.dismiss(id), toast.duration)
    }
  }

  /**
   * Dismiss a specific toast
   */
  dismiss(id: string): void {
    this.toasts = this.toasts.filter(t => t.id !== id)
    this.render()
  }

  /**
   * Clear all toasts
   */
  clearAll(): void {
    this.toasts = []
    this.render()
  }

  /**
   * Render all visible toasts
   */
  private render(): void {
    if (!this.container) return

    // Clear container
    this.container.innerHTML = ''

    // Show only the first maxVisible toasts
    const visibleToasts = this.toasts.slice(0, this.maxVisible)

    visibleToasts.forEach((toast) => {
      const toastEl = this.createToastElement(toast)
      this.container!.appendChild(toastEl)
    })
  }

  /**
   * Create a toast DOM element
   */
  private createToastElement(toast: Toast): HTMLDivElement {
    const toastEl = document.createElement('div')
    toastEl.id = toast.id
    toastEl.className = this.getToastClasses(toast.type)

    const bgColors = {
      info: 'bg-blue-50 border-blue-200',
      success: 'bg-green-50 border-green-200',
      error: 'bg-red-50 border-red-200',
      warning: 'bg-yellow-50 border-yellow-200'
    }

    const textColors = {
      info: 'text-blue-800',
      success: 'text-green-800',
      error: 'text-red-800',
      warning: 'text-yellow-800'
    }

    const icons = {
      info: '✓',
      success: '✓',
      error: '✕',
      warning: '⚠'
    }

    toastEl.innerHTML = `
      <div class="pointer-events-auto rounded-lg border ${bgColors[toast.type]} p-4 shadow-lg animate-slide-in">
        <div class="flex items-start gap-3">
          <span class="text-lg font-bold ${textColors[toast.type]}">${icons[toast.type]}</span>
          <p class="${textColors[toast.type]} text-sm font-medium">${this.escapeHtml(toast.message)}</p>
          <button
            onclick="document.getElementById('${toast.id}')?.remove()"
            class="${textColors[toast.type]} ml-auto hover:opacity-70 transition-opacity"
            aria-label="Close notification"
          >
            ✕
          </button>
        </div>
      </div>
    `

    return toastEl
  }

  /**
   * Get CSS classes for toast type
   */
  private getToastClasses(type: string): string {
    return 'pointer-events-auto'
  }

  /**
   * Escape HTML entities
   */
  private escapeHtml(text: string): string {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}

// Create global toast manager instance
const toastManager = new ToastManager()

// Add CSS animation for slide-in effect
const style = document.createElement('style')
style.textContent = `
  @keyframes slideIn {
    from {
      transform: translateX(-100%);
      opacity: 0;
    }
    to {
      transform: translateX(0);
      opacity: 1;
    }
  }

  .animate-slide-in {
    animation: slideIn 0.3s ease-out;
  }
`
document.head.appendChild(style)

export { toastManager, ToastManager }
