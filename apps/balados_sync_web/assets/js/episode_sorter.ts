/**
 * Episode Sorter
 *
 * Handles switching between chronological (Recent) and popularity-based (Popular)
 * sorting of episodes on the podcast feed page.
 *
 * Usage:
 * <div data-episode-sorter={@encoded_feed}>
 *   (page content with episodes list)
 * </div>
 */

console.log('[EpisodeSorter] Module loading...')

interface Episode {
  id?: string
  title: string
  description?: string
  pub_date?: string
  duration?: number | string
  link?: string
  enclosure?: {
    url: string
    type?: string
  }
  score?: number
  plays?: number
  likes?: number
  [key: string]: any
}

interface PopularEpisodesResponse {
  episodes: Episode[]
}

/**
 * Manages episode sorting UI and AJAX requests
 */
class EpisodeSorter {
  private encodedFeed: string
  private container: HTMLElement | null = null
  private toggleContainer: HTMLElement | null = null
  private episodesContainer: HTMLElement | null = null
  private recentButton: HTMLElement | null = null
  private popularButton: HTMLElement | null = null
  private originalEpisodesHTML: string = ''
  private isLoading: boolean = false
  private currentMode: 'recent' | 'popular' = 'recent'

  constructor(encodedFeed: string) {
    this.encodedFeed = encodedFeed
  }

  /**
   * Initialize the sorter by finding elements and attaching listeners
   */
  init(): void {
    console.log('[EpisodeSorter] Initializing for feed:', this.encodedFeed)

    this.container = document.querySelector('[data-episode-sorter]')
    if (!this.container) {
      console.warn('[EpisodeSorter] Container not found')
      return
    }

    // Find or create toggle container
    this.toggleContainer = this.container.querySelector('.episode-sort-toggle')
    if (!this.toggleContainer) {
      console.log('[EpisodeSorter] Creating toggle container')
      this.createToggleUI()
    } else {
      this.attachToggleListeners()
    }

    // Find episodes container (the list that will be updated)
    this.episodesContainer = this.container.querySelector('[data-episodes-list]')
    if (!this.episodesContainer) {
      // Fallback: look for the episodes section
      const episodesSection = this.container.querySelector('.space-y-4')
      if (episodesSection) {
        this.episodesContainer = episodesSection
      }
    }

    if (!this.episodesContainer) {
      console.warn('[EpisodeSorter] Episodes container not found')
      return
    }

    // Save original HTML for "Recent" mode
    this.originalEpisodesHTML = this.episodesContainer.innerHTML
  }

  /**
   * Create the toggle button UI
   */
  private createToggleUI(): void {
    const toggleDiv = document.createElement('div')
    toggleDiv.className = 'episode-sort-toggle flex gap-2 mb-6 border-b border-zinc-200 pb-4'

    this.recentButton = document.createElement('button')
    this.recentButton.className = 'px-4 py-2 text-sm font-semibold rounded-lg transition-colors ' +
      'bg-blue-600 text-white hover:bg-blue-700'
    this.recentButton.textContent = 'Recent'
    this.recentButton.setAttribute('data-sort', 'recent')

    this.popularButton = document.createElement('button')
    this.popularButton.className = 'px-4 py-2 text-sm font-semibold rounded-lg transition-colors ' +
      'bg-gray-300 text-gray-700 hover:bg-gray-400'
    this.popularButton.textContent = 'Popular'
    this.popularButton.setAttribute('data-sort', 'popular')

    toggleDiv.appendChild(this.recentButton)
    toggleDiv.appendChild(this.popularButton)

    // Insert before episodes list
    if (this.episodesContainer && this.episodesContainer.parentNode) {
      this.episodesContainer.parentNode.insertBefore(toggleDiv, this.episodesContainer)
      this.toggleContainer = toggleDiv
    }

    this.attachToggleListeners()
  }

  /**
   * Attach click listeners to toggle buttons
   */
  private attachToggleListeners(): void {
    const recentBtn = this.toggleContainer?.querySelector('[data-sort="recent"]')
    const popularBtn = this.toggleContainer?.querySelector('[data-sort="popular"]')

    if (recentBtn) {
      recentBtn.addEventListener('click', () => this.switchToRecent())
    }

    if (popularBtn) {
      popularBtn.addEventListener('click', () => this.switchToPopular())
    }
  }

  /**
   * Switch to recent (chronological) view
   */
  private switchToRecent(): void {
    if (this.currentMode === 'recent' || this.isLoading) return

    console.log('[EpisodeSorter] Switching to Recent')
    this.currentMode = 'recent'
    this.updateButtonStates()

    if (this.episodesContainer) {
      this.episodesContainer.innerHTML = this.originalEpisodesHTML
    }
  }

  /**
   * Switch to popular view (fetches from API)
   */
  private switchToPopular(): void {
    if (this.currentMode === 'popular' || this.isLoading) return

    console.log('[EpisodeSorter] Switching to Popular')
    this.isLoading = true
    this.updateButtonStates()

    this.fetchPopularEpisodes()
      .then(episodes => this.renderPopularEpisodes(episodes))
      .catch(error => this.handleError(error))
      .finally(() => {
        this.isLoading = false
        this.updateButtonStates()
      })
  }

  /**
   * Fetch popular episodes from API
   */
  private fetchPopularEpisodes(): Promise<Episode[]> {
    const url = new URL('/api/v1/public/trending/episodes', window.location.origin)
    url.searchParams.set('feed', this.encodedFeed)
    url.searchParams.set('limit', '20')

    console.log('[EpisodeSorter] Fetching from:', url.toString())

    return fetch(url.toString())
      .then(response => {
        if (!response.ok) {
          throw new Error(`API error: ${response.status}`)
        }
        return response.json()
      })
      .then((data: PopularEpisodesResponse) => {
        if (!Array.isArray(data.episodes)) {
          throw new Error('Invalid response format')
        }
        return data.episodes
      })
  }

  /**
   * Render popular episodes
   */
  private renderPopularEpisodes(episodes: Episode[]): void {
    if (!this.episodesContainer) return

    if (episodes.length === 0) {
      this.episodesContainer.innerHTML = '<div class="text-center text-gray-500 py-8">No popular episodes found</div>'
      this.currentMode = 'popular'
      return
    }

    const html = episodes.map(episode => this.renderEpisodeCard(episode)).join('')
    this.episodesContainer.innerHTML = html
    this.currentMode = 'popular'
  }

  /**
   * Render a single episode card with popularity stats
   */
  private renderEpisodeCard(episode: Episode): string {
    const title = this.escapeHtml(episode.title || 'Unknown Episode')
    const description = this.escapeHtml(episode.description || '')

    // Format date if available
    let dateStr = ''
    if (episode.pub_date) {
      const date = new Date(episode.pub_date)
      if (!isNaN(date.getTime())) {
        const now = new Date()
        const diffMs = now.getTime() - date.getTime()
        const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))
        if (diffDays === 0) {
          dateStr = 'Today'
        } else if (diffDays === 1) {
          dateStr = 'Yesterday'
        } else if (diffDays < 30) {
          dateStr = `${diffDays} days ago`
        } else {
          dateStr = date.toLocaleDateString()
        }
      }
    }

    // Render stats
    const score = episode.score ?? 0
    const plays = episode.plays ?? 0
    const likes = episode.likes ?? 0

    return `
      <div class="bg-white border border-zinc-200 rounded-lg p-4">
        <h3 class="font-semibold text-zinc-900">${title}</h3>

        <div class="flex gap-4 text-sm text-zinc-500 mt-2">
          ${dateStr ? `<span>${dateStr}</span>` : ''}
          ${episode.duration ? `<span>${this.formatDuration(episode.duration)}</span>` : ''}
        </div>

        ${description ? `<p class="text-sm text-zinc-700 mt-2 line-clamp-3">${description}</p>` : ''}

        <!-- Popularity Stats -->
        <div class="mt-3 p-2 bg-blue-50 rounded text-sm text-zinc-600">
          <strong>Popularity:</strong> Score ${score} • ${plays} plays • ${likes} likes
        </div>

        <!-- Links -->
        <div class="mt-4 flex gap-3">
          ${episode.link ? `
            <a href="${this.escapeHtml(episode.link)}" target="_blank" rel="noopener noreferrer"
               class="text-blue-600 hover:underline text-sm">
              Read Article →
            </a>
          ` : ''}
          ${episode.enclosure ? `
            <a href="${this.escapeHtml(episode.enclosure.url)}" target="_blank" rel="noopener noreferrer"
               class="text-blue-600 hover:underline text-sm">
              Download/Play Episode →
            </a>
          ` : ''}
        </div>
      </div>
    `
  }

  /**
   * Format duration in seconds to readable format
   */
  private formatDuration(duration: number | string): string {
    const seconds = typeof duration === 'string' ? parseInt(duration, 10) : duration
    if (isNaN(seconds)) return ''

    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)

    if (hours > 0) {
      return `${hours}h ${minutes}m`
    } else if (minutes > 0) {
      return `${minutes}m`
    } else {
      return `${seconds}s`
    }
  }

  /**
   * Update button styles based on current mode
   */
  private updateButtonStates(): void {
    const recentBtn = this.toggleContainer?.querySelector('[data-sort="recent"]') as HTMLElement
    const popularBtn = this.toggleContainer?.querySelector('[data-sort="popular"]') as HTMLElement

    if (recentBtn) {
      if (this.currentMode === 'recent') {
        recentBtn.className = 'px-4 py-2 text-sm font-semibold rounded-lg transition-colors ' +
          'bg-blue-600 text-white hover:bg-blue-700'
        recentBtn.disabled = this.isLoading
      } else {
        recentBtn.className = 'px-4 py-2 text-sm font-semibold rounded-lg transition-colors ' +
          'bg-gray-300 text-gray-700 hover:bg-gray-400'
        recentBtn.disabled = false
      }
    }

    if (popularBtn) {
      if (this.currentMode === 'popular') {
        popularBtn.className = 'px-4 py-2 text-sm font-semibold rounded-lg transition-colors ' +
          'bg-blue-600 text-white hover:bg-blue-700' + (this.isLoading ? ' opacity-75' : '')
        popularBtn.disabled = this.isLoading
      } else {
        popularBtn.className = 'px-4 py-2 text-sm font-semibold rounded-lg transition-colors ' +
          'bg-gray-300 text-gray-700 hover:bg-gray-400'
        popularBtn.disabled = false
      }
    }
  }

  /**
   * Handle errors
   */
  private handleError(error: Error): void {
    console.error('[EpisodeSorter] Error:', error)
    if (this.episodesContainer) {
      this.episodesContainer.innerHTML = `
        <div class="text-center text-red-600 py-8">
          <p>Failed to load popular episodes</p>
          <p class="text-sm text-gray-500 mt-1">${this.escapeHtml(error.message)}</p>
        </div>
      `
    }
    this.currentMode = 'recent'
  }

  /**
   * Escape HTML to prevent XSS
   */
  private escapeHtml(text: string): string {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}

// Auto-initialize if data attribute present
const initEpisodeSorting = () => {
  const pageElement = document.querySelector('[data-episode-sorter]')
  if (pageElement) {
    const encodedFeed = pageElement.getAttribute('data-episode-sorter')
    if (encodedFeed) {
      const sorter = new EpisodeSorter(encodedFeed)
      sorter.init()
    }
  }
}

// Handle DOMContentLoaded
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initEpisodeSorting)
} else {
  initEpisodeSorting()
}
