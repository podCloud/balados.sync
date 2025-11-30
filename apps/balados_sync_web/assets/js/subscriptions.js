/**
 * Auto-refresh metadata for subscriptions page
 *
 * This script enhances the subscriptions page by automatically fetching
 * metadata for subscriptions that don't have it yet (async loading).
 *
 * It's a progressive enhancement - the page works fine without JavaScript,
 * but with JS enabled, users get fresh metadata loaded automatically.
 */

document.addEventListener("DOMContentLoaded", () => {
  // Find all subscription cards
  const subscriptionCards = document.querySelectorAll(
    "[data-subscription-feed]"
  );

  // For each subscription card, check if it needs metadata
  subscriptionCards.forEach((card) => {
    const encodedFeed = card.dataset.subscriptionFeed;
    const hasMetadata = card.dataset.hasMetadata === "true";

    // Only fetch if metadata is missing
    if (!hasMetadata) {
      fetchMetadata(encodedFeed, card);
    }
  });
});

/**
 * Fetch metadata for a subscription via AJAX
 * @param {string} encodedFeed - Base64-encoded feed URL
 * @param {HTMLElement} cardElement - The subscription card element
 */
async function fetchMetadata(encodedFeed, cardElement) {
  try {
    const response = await fetch(
      `/api/v1/subscriptions/${encodedFeed}/metadata`
    );

    if (!response.ok) {
      console.error("Failed to fetch metadata:", response.status);
      return;
    }

    const data = await response.json();
    const metadata = data.metadata;

    // Update card title
    const titleEl = cardElement.querySelector("[data-subscription-title]");
    if (titleEl && metadata.title) {
      titleEl.textContent = metadata.title;
    }

    // Update card description
    const descEl = cardElement.querySelector("[data-subscription-description]");
    if (descEl && metadata.description) {
      descEl.textContent = metadata.description;
    }

    // Update cover image
    const coverEl = cardElement.querySelector("[data-subscription-cover]");
    if (coverEl && metadata.cover) {
      coverEl.src = metadata.cover.src;
      coverEl.alt = metadata.title || "Podcast Cover";
      coverEl.classList.remove("hidden");
    }

    // Remove loading state
    const loadingEl = cardElement.querySelector("[data-subscription-loading]");
    if (loadingEl) {
      loadingEl.classList.add("hidden");
    }
  } catch (error) {
    console.error("Failed to fetch metadata:", error);
    // Silently fail - the page still works with placeholder text
  }
}
