function initPrivacyManager() {
  // Get all podcast items
  const podcastItems = document.querySelectorAll('.podcast-item');

  podcastItems.forEach((item) => {
    const editBtn = item.querySelector('.edit-btn');
    const cancelBtn = item.querySelector('.cancel-btn');
    const changeBtn = item.querySelector('.change-btn');
    const editControls = item.querySelector('.edit-controls');
    const privacySelect = item.querySelector('.privacy-select');
    const feed = item.dataset.feed;
    const currentPrivacy = item.dataset.currentPrivacy;

    // Set initial select value
    if (privacySelect) {
      privacySelect.value = currentPrivacy;
    }

    // Toggle edit mode on pencil click
    editBtn?.addEventListener('click', (e) => {
      e.preventDefault();
      editControls?.classList.remove('hidden');
      privacySelect?.focus();
    });

    // Hide edit mode on cancel click
    cancelBtn?.addEventListener('click', (e) => {
      e.preventDefault();
      editControls?.classList.add('hidden');
      // Reset select to current value
      if (privacySelect) {
        privacySelect.value = currentPrivacy;
      }
    });

    // Handle change button click
    changeBtn?.addEventListener('click', async (e) => {
      e.preventDefault();

      const newPrivacy = privacySelect?.value;

      if (!newPrivacy || newPrivacy === currentPrivacy) {
        editControls?.classList.add('hidden');
        return;
      }

      try {
        // Show loading state
        changeBtn.disabled = true;
        changeBtn.textContent = 'Updating...';

        // Send AJAX request
        const response = await fetch(`/privacy-manager/${feed}`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
            'X-Requested-With': 'XMLHttpRequest'
          },
          body: `privacy=${encodeURIComponent(newPrivacy)}`
        });

        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }

        // Move the podcast item to the correct section
        movePodcastToSection(item, feed, currentPrivacy, newPrivacy);

        // Hide edit controls
        editControls?.classList.add('hidden');
      } catch (error) {
        console.error('Error updating privacy:', error);
        alert('Error updating privacy level. Please try again.');
        changeBtn.disabled = false;
        changeBtn.textContent = 'Change';
      }
    });
  });
}

function movePodcastToSection(item, feed, oldPrivacy, newPrivacy) {
  // Get the target section
  const targetSection = document.querySelector(`[data-privacy-group="${newPrivacy}"]`);
  const podcastsList = targetSection?.querySelector('.podcasts-list');

  if (!targetSection || !podcastsList) return;

  // Remove empty state if present
  const emptyState = podcastsList.querySelector('.empty-state');
  if (emptyState) {
    emptyState.remove();
  }

  // Clone and move the item
  const clonedItem = item.cloneNode(true);
  item.remove();

  // Re-attach event listeners to the cloned item
  const editBtn = clonedItem.querySelector('.edit-btn');
  const cancelBtn = clonedItem.querySelector('.cancel-btn');
  const changeBtn = clonedItem.querySelector('.change-btn');
  const editControls = clonedItem.querySelector('.edit-controls');
  const privacySelect = clonedItem.querySelector('.privacy-select');

  // Reset the item data attribute
  clonedItem.dataset.currentPrivacy = newPrivacy;

  // Re-attach all event listeners
  editBtn?.addEventListener('click', (e) => {
    e.preventDefault();
    editControls?.classList.remove('hidden');
    privacySelect?.focus();
  });

  cancelBtn?.addEventListener('click', (e) => {
    e.preventDefault();
    editControls?.classList.add('hidden');
    if (privacySelect) {
      privacySelect.value = newPrivacy;
    }
  });

  changeBtn?.addEventListener('click', async (e) => {
    e.preventDefault();
    const selectedPrivacy = privacySelect?.value;

    if (!selectedPrivacy || selectedPrivacy === newPrivacy) {
      editControls?.classList.add('hidden');
      return;
    }

    try {
      changeBtn.disabled = true;
      changeBtn.textContent = 'Updating...';

      const response = await fetch(`/privacy-manager/${feed}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: `privacy=${encodeURIComponent(selectedPrivacy)}`
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      movePodcastToSection(clonedItem, feed, newPrivacy, selectedPrivacy);
      editControls?.classList.add('hidden');
    } catch (error) {
      console.error('Error updating privacy:', error);
      alert('Error updating privacy level. Please try again.');
      changeBtn.disabled = false;
      changeBtn.textContent = 'Change';
    }
  });

  // Add the cloned item to the target section
  podcastsList.appendChild(clonedItem);

  // Update counts
  updateCounts();
}

function updateCounts() {
  // Get all privacy groups
  const groups = {
    public: document.querySelectorAll('[data-privacy-group="public"] .podcast-item').length,
    anonymous: document.querySelectorAll('[data-privacy-group="anonymous"] .podcast-item').length,
    private: document.querySelectorAll('[data-privacy-group="private"] .podcast-item').length
  };

  // Update count badges
  document.querySelectorAll('.count-badge').forEach((badge) => {
    const section = badge.closest('[data-privacy-group]');
    if (section) {
      const privacy = section.dataset.privacyGroup;
      badge.textContent = `(${groups[privacy]})`;
    }
  });

  // Update summary
  document.querySelectorAll('.summary-count').forEach((count) => {
    const privacy = count.dataset.privacy;
    count.textContent = groups[privacy];
  });

  // Show/hide empty states
  Object.entries(groups).forEach(([privacy, count]) => {
    const section = document.querySelector(`[data-privacy-group="${privacy}"] .podcasts-list`);
    if (!section) return;

    const emptyState = section.querySelector('.empty-state');
    if (count === 0 && !emptyState) {
      const div = document.createElement('div');
      div.className = 'px-4 py-8 sm:p-8 text-center text-zinc-500 empty-state';
      div.innerHTML = `<p>No ${privacy} podcasts yet.</p>`;
      section.appendChild(div);
    } else if (count > 0 && emptyState) {
      emptyState.remove();
    }
  });
}

// Initialize on page load if this is the privacy manager page
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    if (document.querySelector('[data-page="privacy-manager"]')) {
      initPrivacyManager();
    }
  });
} else {
  // DOM is already loaded
  if (document.querySelector('[data-page="privacy-manager"]')) {
    initPrivacyManager();
  }
}
