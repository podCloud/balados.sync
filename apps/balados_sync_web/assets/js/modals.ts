/**
 * Modal management for login and subscription forms
 */

interface ModalOptions {
  modalId: string;
  triggerSelector: string;
  closeSelector?: string;
}

export class ModalManager {
  private modal: HTMLElement | null;
  private triggers: NodeListOf<Element>;
  private closeButtons: NodeListOf<Element>;

  constructor(options: ModalOptions) {
    this.modal = document.getElementById(options.modalId);
    this.triggers = document.querySelectorAll(options.triggerSelector);
    this.closeButtons = options.closeSelector
      ? this.modal?.querySelectorAll(options.closeSelector) || []
      : [];

    this.init();
  }

  private init(): void {
    if (!this.modal) return;

    // Show modal on trigger click
    this.triggers.forEach((trigger) => {
      trigger.addEventListener("click", (e) => {
        e.preventDefault();
        this.show();
      });
    });

    // Hide modal on close button click
    this.closeButtons.forEach((btn) => {
      btn.addEventListener("click", () => {
        this.hide();
      });
    });

    // Hide modal on background click
    this.modal.addEventListener("click", (e) => {
      if (e.target === this.modal) {
        this.hide();
      }
    });

    // Hide modal on Escape key
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !this.modal?.classList.contains("hidden")) {
        this.hide();
      }
    });
  }

  public show(): void {
    this.modal?.classList.remove("hidden");
    // Focus first input
    const firstInput = this.modal?.querySelector("input");
    firstInput?.focus();
  }

  public hide(): void {
    this.modal?.classList.add("hidden");
  }
}

// Initialize modals when DOM is ready
export function initModals(): void {
  // Login modal
  const loginModal = new ModalManager({
    modalId: "login-modal",
    triggerSelector: ".js-show-login-modal",
    closeSelector: ".js-hide-modal",
  });

  // Subscribe modal
  const subscribeModal = new ModalManager({
    modalId: "subscribe-modal",
    triggerSelector: ".js-show-subscribe-modal",
    closeSelector: ".js-hide-modal",
  });
}

// Auto-initialize on load
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initModals);
} else {
  initModals();
}
