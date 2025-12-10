/**
 * Timeline Filter System
 * Handles client-side filtering of timeline events by type and visibility
 */

export type EventType = 'play' | 'subscribe' | 'all'
export type FilterMode = 'all' | 'me' | 'public'

interface FilterState {
  mode: FilterMode
  eventTypes: EventType[]
}

interface TimelineEvent {
  id: string
  event_type: string
  user_id?: string
  privacy?: string
}

class TimelineFilter {
  private state: FilterState = {
    mode: 'all',
    eventTypes: ['play', 'subscribe']
  }

  private allEvents: TimelineEvent[] = []
  private filteredEvents: TimelineEvent[] = []
  private onFilterChange: ((events: TimelineEvent[]) => void) | null = null

  /**
   * Initialize filter with DOM elements
   */
  initialize(containerId: string): void {
    const container = document.getElementById(containerId)
    if (!container) {
      console.warn(`Container ${containerId} not found for timeline filter`)
      return
    }

    // Get all event elements
    this.allEvents = this.extractEventsFromDOM(container)

    // Setup filter UI event listeners
    this.setupFilterListeners()

    // Apply initial filter
    this.applyFilter()
  }

  /**
   * Extract event data from DOM
   */
  private extractEventsFromDOM(container: HTMLElement): TimelineEvent[] {
    const events: TimelineEvent[] = []
    const eventElements = container.querySelectorAll('[data-event-id]')

    eventElements.forEach((el) => {
      const event: TimelineEvent = {
        id: el.getAttribute('data-event-id') || '',
        event_type: el.getAttribute('data-event-type') || 'unknown',
        user_id: el.getAttribute('data-user-id'),
        privacy: el.getAttribute('data-privacy')
      }
      events.push(event)
    })

    return events
  }

  /**
   * Setup filter UI event listeners
   */
  private setupFilterListeners(): void {
    // Mode filter buttons (All / Me / Public)
    document.querySelectorAll('[data-filter-mode]').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.preventDefault()
        const mode = (e.currentTarget as HTMLElement).getAttribute('data-filter-mode') as FilterMode
        this.setMode(mode)
      })
    })

    // Event type checkboxes
    document.querySelectorAll('[data-filter-event-type]').forEach((checkbox) => {
      checkbox.addEventListener('change', (e) => {
        const type = (e.currentTarget as HTMLInputElement).getAttribute('data-filter-event-type') as EventType
        const isChecked = (e.currentTarget as HTMLInputElement).checked
        this.toggleEventType(type, isChecked)
      })
    })
  }

  /**
   * Set filter mode
   */
  setMode(mode: FilterMode): void {
    this.state.mode = mode
    this.updateModeUI()
    this.applyFilter()
  }

  /**
   * Toggle event type filter
   */
  toggleEventType(type: EventType, enabled: boolean): void {
    if (type === 'all') {
      // If 'all' is selected, clear other types
      this.state.eventTypes = enabled ? ['play', 'subscribe'] : []
    } else {
      if (enabled) {
        if (!this.state.eventTypes.includes(type)) {
          this.state.eventTypes.push(type)
        }
      } else {
        this.state.eventTypes = this.state.eventTypes.filter(t => t !== type)
      }
    }
    this.updateEventTypeUI()
    this.applyFilter()
  }

  /**
   * Apply current filter to events
   */
  private applyFilter(): void {
    this.filteredEvents = this.allEvents.filter((event) => {
      // Filter by mode (All / Me / Public)
      if (this.state.mode === 'me' && !event.user_id) {
        return false
      }
      if (this.state.mode === 'public' && event.privacy !== 'public') {
        return false
      }

      // Filter by event type
      if (!this.state.eventTypes.includes(event.event_type as EventType)) {
        return false
      }

      return true
    })

    // Update UI visibility
    this.updateEventVisibility()

    // Trigger callback
    if (this.onFilterChange) {
      this.onFilterChange(this.filteredEvents)
    }
  }

  /**
   * Update visibility of event elements
   */
  private updateEventVisibility(): void {
    document.querySelectorAll('[data-event-id]').forEach((el) => {
      const eventId = el.getAttribute('data-event-id')
      const isVisible = this.filteredEvents.some(e => e.id === eventId)
      ;(el as HTMLElement).style.display = isVisible ? '' : 'none'
    })
  }

  /**
   * Update mode UI (button active states)
   */
  private updateModeUI(): void {
    document.querySelectorAll('[data-filter-mode]').forEach((btn) => {
      const mode = btn.getAttribute('data-filter-mode')
      if (mode === this.state.mode) {
        btn.classList.add('active', 'bg-blue-600', 'text-white')
        btn.classList.remove('bg-white', 'text-zinc-700')
      } else {
        btn.classList.remove('active', 'bg-blue-600', 'text-white')
        btn.classList.add('bg-white', 'text-zinc-700')
      }
    })
  }

  /**
   * Update event type UI (checkbox states)
   */
  private updateEventTypeUI(): void {
    document.querySelectorAll('[data-filter-event-type]').forEach((checkbox) => {
      const type = checkbox.getAttribute('data-filter-event-type') as EventType
      ;(checkbox as HTMLInputElement).checked = this.state.eventTypes.includes(type)
    })
  }

  /**
   * Set callback for filter changes
   */
  onFilterChanged(callback: (events: TimelineEvent[]) => void): void {
    this.onFilterChange = callback
  }

  /**
   * Get current filter state
   */
  getFilterState(): FilterState {
    return { ...this.state }
  }

  /**
   * Get filtered events count
   */
  getFilteredCount(): number {
    return this.filteredEvents.length
  }
}

// Create global filter instance
const timelineFilter = new TimelineFilter()

export { timelineFilter, TimelineFilter }
