/**
 * Privacy Manager Page - Inline edit mode for podcast privacy levels
 *
 * Handles the pencil icon edit mode for quickly changing podcast privacy levels
 * with AJAX updates and DOM manipulation.
 */

interface PodcastItem extends HTMLElement {
  dataset: DOMStringMap & {
    feed: string
    currentPrivacy: string
  }
}

function attachPodcastItemListeners(item: PodcastItem): void {
  const editBtn = item.querySelector<HTMLButtonElement>('.edit-btn')
  const cancelBtn = item.querySelector<HTMLButtonElement>('.cancel-btn')
  const changeBtn = item.querySelector<HTMLButtonElement>('.change-btn')
  const unsubscribeBtn = item.querySelector<HTMLButtonElement>('.unsubscribe-btn')
  const editControls = item.querySelector<HTMLDivElement>('.edit-controls')
  const privacySelect = item.querySelector<HTMLSelectElement>('.privacy-select')
  const feed = item.dataset.feed
  const currentPrivacy = item.dataset.currentPrivacy

  // Set initial select value
  if (privacySelect) {
    privacySelect.value = currentPrivacy
  }

  // Toggle edit mode on pencil click
  editBtn?.addEventListener('click', (e) => {
    e.preventDefault()
    editControls?.classList.remove('hidden')
    privacySelect?.focus()
  })

  // Hide edit mode on cancel click
  cancelBtn?.addEventListener('click', (e) => {
    e.preventDefault()
    editControls?.classList.add('hidden')
    // Reset select to current value
    if (privacySelect) {
      privacySelect.value = currentPrivacy
    }
  })

  // Handle unsubscribe/remove
  unsubscribeBtn?.addEventListener('click', async (e) => {
    e.preventDefault()

    if (!confirm('Are you sure you want to remove this subscription?')) {
      return
    }

    try {
      unsubscribeBtn.disabled = true
      unsubscribeBtn.textContent = 'Removing...'

      const response = await fetch(`/podcasts/${feed}/subscribe`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': getCsrfToken(),
          'X-Requested-With': 'XMLHttpRequest',
        },
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      // Remove the podcast item from the DOM
      item.remove()

      // Update counts
      updateCounts()
    } catch (error) {
      console.error('Error removing subscription:', error)
      alert('Error removing subscription. Please try again.')
      unsubscribeBtn.disabled = false
      unsubscribeBtn.textContent = 'Remove'
    }
  })

  // Handle change button click
  changeBtn?.addEventListener('click', async (e) => {
    e.preventDefault()

    const newPrivacy = privacySelect?.value

    if (!newPrivacy || newPrivacy === currentPrivacy) {
      editControls?.classList.add('hidden')
      return
    }

    try {
      // Show loading state
      changeBtn.disabled = true
      changeBtn.textContent = 'Updating...'

      // Send AJAX request
      const response = await fetch(`/privacy-manager/${feed}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-CSRF-Token': getCsrfToken(),
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: `privacy=${encodeURIComponent(newPrivacy)}`,
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      // Move the podcast item to the correct section
      movePodcastToSection(item, feed, currentPrivacy, newPrivacy)

      // Hide edit controls
      editControls?.classList.add('hidden')
    } catch (error) {
      console.error('Error updating privacy:', error)
      alert('Error updating privacy level. Please try again.')
      changeBtn.disabled = false
      changeBtn.textContent = 'Change'
    }
  })
}

function initPrivacyManagerPage(): void {
  const podcastItems = document.querySelectorAll('.podcast-item') as NodeListOf<PodcastItem>

  podcastItems.forEach((item) => {
    attachPodcastItemListeners(item)
  })
}

function movePodcastToSection(
  item: PodcastItem,
  feed: string,
  oldPrivacy: string,
  newPrivacy: string
): void {
  // Get the target section
  const targetSection = document.querySelector(`[data-privacy-group="${newPrivacy}"]`)
  const podcastsList = targetSection?.querySelector('.podcasts-list')

  if (!targetSection || !podcastsList) return

  // Remove empty state if present
  const emptyState = podcastsList.querySelector('.empty-state')
  if (emptyState) {
    emptyState.remove()
  }

  // Clone and move the item
  const clonedItem = item.cloneNode(true) as PodcastItem
  item.remove()

  // Reset the item data attribute
  clonedItem.dataset.currentPrivacy = newPrivacy

  // Re-attach event listeners to the cloned item
  attachPodcastItemListeners(clonedItem)

  // Add the cloned item to the target section
  podcastsList.appendChild(clonedItem)

  // Update counts
  updateCounts()
}

function updateCounts(): void {
  // Get all privacy groups
  const groups = {
    public: document.querySelectorAll('[data-privacy-group="public"] .podcast-item').length,
    anonymous: document.querySelectorAll('[data-privacy-group="anonymous"] .podcast-item').length,
    private: document.querySelectorAll('[data-privacy-group="private"] .podcast-item').length,
  }

  // Update count badges
  document.querySelectorAll('.count-badge').forEach((badge) => {
    const section = badge.closest('[data-privacy-group]')
    if (section) {
      const privacy = (section as HTMLElement).dataset.privacyGroup
      badge.textContent = `(${groups[privacy as keyof typeof groups]})`
    }
  })

  // Update summary
  document.querySelectorAll('.summary-count').forEach((count) => {
    const privacy = (count as HTMLElement).dataset.privacy
    ;(count as HTMLElement).textContent = String(groups[privacy as keyof typeof groups])
  })

  // Show/hide empty states
  Object.entries(groups).forEach(([privacy, count]) => {
    const section = document.querySelector(`[data-privacy-group="${privacy}"] .podcasts-list`)
    if (!section) return

    const emptyState = section.querySelector('.empty-state')
    if (count === 0 && !emptyState) {
      const div = document.createElement('div')
      div.className = 'px-4 py-8 sm:p-8 text-center text-zinc-500 empty-state'
      div.innerHTML = `<p>No ${privacy} podcasts yet.</p>`
      section.appendChild(div)
    } else if (count > 0 && emptyState) {
      emptyState.remove()
    }
  })
}

function getCsrfToken(): string {
  const element = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
  return element?.getAttribute('content') || ''
}

// Initialize on page load if this is the privacy manager page
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    if (document.querySelector('[data-page="privacy-manager"]')) {
      initPrivacyManagerPage()
    }
  })
} else {
  // DOM is already loaded
  if (document.querySelector('[data-page="privacy-manager"]')) {
    initPrivacyManagerPage()
  }
}
