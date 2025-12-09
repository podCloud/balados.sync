export class PrivacyBadge {
  private encodedFeed: string

  constructor(encodedFeed: string) {
    this.encodedFeed = encodedFeed
  }

  init(): void {
    const changeBtn = document.getElementById('change-privacy-btn')
    const modal = document.getElementById('privacy-change-modal')

    if (!changeBtn || !modal) return

    changeBtn.addEventListener('click', () => this.openModal())

    // Modal handlers
    const saveBtn = document.getElementById('privacy-save-btn')
    const cancelBtn = document.getElementById('privacy-cancel-btn')

    saveBtn?.addEventListener('click', () => this.savePrivacy())
    cancelBtn?.addEventListener('click', () => this.closeModal())

    // Close on backdrop click
    modal.addEventListener('click', (e) => {
      if (e.target === modal) this.closeModal()
    })
  }

  private openModal(): void {
    const modal = document.getElementById('privacy-change-modal')
    if (modal) modal.classList.remove('hidden')
  }

  private closeModal(): void {
    const modal = document.getElementById('privacy-change-modal')
    if (modal) modal.classList.add('hidden')
    this.clearMessage()
  }

  private getCsrfToken(): string {
    const element = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
    return element?.getAttribute('content') || ''
  }

  private async savePrivacy(): Promise<void> {
    const selected = document.querySelector(
      'input[name="privacy"]:checked'
    ) as HTMLInputElement
    if (!selected) return

    const privacy = selected.value
    const saveBtn = document.getElementById('privacy-save-btn')
    const messageDiv = document.getElementById('privacy-modal-message')

    if (!saveBtn || !messageDiv) return

    // Show loading state
    saveBtn.disabled = true
    saveBtn.textContent = 'Saving...'

    try {
      const response = await fetch(`/privacy-manager/${this.encodedFeed}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-CSRF-Token': this.getCsrfToken(),
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: `privacy=${encodeURIComponent(privacy)}`
      })

      if (response.ok) {
        // Update badge and close modal
        this.updateBadge(privacy)
        this.showMessage('Privacy updated successfully!', 'success')
        setTimeout(() => this.closeModal(), 500)
      } else {
        this.showMessage('Failed to update privacy', 'error')
      }
    } catch (error) {
      console.error('Error updating privacy:', error)
      this.showMessage('Error updating privacy', 'error')
    } finally {
      saveBtn.disabled = false
      saveBtn.textContent = 'Save Changes'
    }
  }

  private updateBadge(privacy: string): void {
    const badge = document.getElementById('privacy-badge')
    if (!badge) return

    const icons: Record<string, string> = {
      public: '🔓',
      anonymous: '👤',
      private: '🔒'
    }

    const colors: Record<string, string> = {
      public: 'bg-blue-100 text-blue-900 border-blue-300',
      anonymous: 'bg-purple-100 text-purple-900 border-purple-300',
      private: 'bg-red-100 text-red-900 border-red-300'
    }

    // Update badge classes
    badge.className = `mt-6 inline-flex items-center gap-2 px-4 py-2 rounded-lg border ${colors[privacy]}`

    // Clear existing content
    badge.innerHTML = ''

    // Create icon span
    const iconSpan = document.createElement('span')
    iconSpan.textContent = icons[privacy]
    badge.appendChild(iconSpan)

    // Create text span
    const textSpan = document.createElement('span')
    textSpan.className = 'font-medium'
    const textContent = document.createElement('span')
    textContent.appendChild(document.createTextNode('Your activities are '))
    const strongText = document.createElement('strong')
    strongText.textContent = privacy
    textContent.appendChild(strongText)
    textSpan.appendChild(textContent)
    badge.appendChild(textSpan)

    // Create change button
    const changeBtn = document.createElement('button')
    changeBtn.type = 'button'
    changeBtn.id = 'change-privacy-btn'
    changeBtn.className = 'ml-2 text-sm opacity-75 hover:opacity-100 cursor-pointer transition'
    changeBtn.textContent = '✎ Change'
    changeBtn.addEventListener('click', () => this.openModal())
    badge.appendChild(changeBtn)
  }

  private showMessage(message: string, type: 'success' | 'error'): void {
    const messageDiv = document.getElementById('privacy-modal-message')
    if (!messageDiv) return

    const bgColor = type === 'success' ? 'bg-green-50 text-green-800' : 'bg-red-50 text-red-800'
    messageDiv.className = `mt-4 text-sm ${bgColor} p-3 rounded`
    messageDiv.textContent = message
    messageDiv.classList.remove('hidden')
  }

  private clearMessage(): void {
    const messageDiv = document.getElementById('privacy-modal-message')
    if (messageDiv) {
      messageDiv.classList.add('hidden')
      messageDiv.textContent = ''
    }
  }
}

// Auto-init
const initPrivacyBadge = () => {
  const badge = document.getElementById('privacy-badge')
  if (badge) {
    const encodedFeed = badge.getAttribute('data-feed')
    if (encodedFeed) {
      const privacyBadge = new PrivacyBadge(encodedFeed)
      privacyBadge.init()
    }
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initPrivacyBadge)
} else {
  initPrivacyBadge()
}
