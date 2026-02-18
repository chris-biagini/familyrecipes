class RecipeStateManager {
  constructor() {
    this.recipeId = document.body.dataset.recipeId;
    this.versionHash = document.body.dataset.versionHash;
    this.STORED_STATE_TTL = 48 * 60 * 60 * 1000; // 48h

    this.crossableItemNodes = document.querySelectorAll(
      '.ingredients li, .instructions p'
    );
    this.sectionTogglerNodes = document.querySelectorAll('section h2');

    // track the last raw scale input (defaults to "1")
    this.lastScaleInput = '1';

    this.init();
  }

  init() {
    this.setupEventListeners();
    this.loadRecipeState();
    this.setupScaleButton();
    this.updateScaleButtonLabel(); // ensure correct label on load
  }

  saveRecipeState() {
    const currentRecipeState = {
      lastInteractionTime: Date.now(),
      versionHash: this.versionHash,
      crossableItemState: {},
      scaleFactor: this.lastScaleInput // persist the raw user input
    };

    this.crossableItemNodes.forEach((node, idx) => {
      currentRecipeState.crossableItemState[idx] =
        node.classList.contains('crossed-off');
    });

    localStorage.setItem(
      `saved-state-for-${this.recipeId}`,
      JSON.stringify(currentRecipeState)
    );
  }

  loadRecipeState() {
    const raw = localStorage.getItem(`saved-state-for-${this.recipeId}`);
    if (!raw) return;

    let stored;
    try {
      stored = JSON.parse(raw);
    } catch {
      console.warn('Corrupt state JSON. Resetting.');
      return this.saveRecipeState();
    }

    const {
      versionHash,
      lastInteractionTime,
      crossableItemState,
      scaleFactor
    } = stored;

    if (
      versionHash !== this.versionHash ||
      Date.now() - lastInteractionTime > this.STORED_STATE_TTL
    ) {
      console.info('Saved state stale or mismatched. Overwriting.');
      return this.saveRecipeState();
    }

    // re-apply crossed-off state
    this.crossableItemNodes.forEach((node, idx) => {
      if (crossableItemState[idx]) node.classList.add('crossed-off');
    });

    // re-apply scale if we have one
    if (scaleFactor) {
      this.lastScaleInput = scaleFactor;
      this.applyScale(scaleFactor);
      this.updateScaleButtonLabel();
    }
  }

  setupEventListeners() {
    // cross-off on click or keyboard
    this.crossableItemNodes.forEach(node => {
      node.tabIndex = 0;
      node.addEventListener('click', (e) => {
        if (e.target.closest('a')) return;
        node.classList.toggle('crossed-off');
        this.saveRecipeState();
      });
      node.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          if (e.target.closest('a')) return;
          e.preventDefault();
          node.classList.toggle('crossed-off');
          this.saveRecipeState();
        }
      });
    });

    // header toggles entire section
    this.sectionTogglerNodes.forEach(h2 => {
      h2.addEventListener('click', () => {
        const section = h2.closest('section');
        const items = section.querySelectorAll(
          '.ingredients li, .instructions p'
        );
        const allCrossed = Array.from(items).every(i =>
          i.classList.contains('crossed-off')
        );
        items.forEach(i => i.classList.toggle('crossed-off', !allCrossed));
        this.saveRecipeState();
      });
    });
  }

  setupScaleButton() {
    const btn = document.getElementById('scale-button');
    if (!btn) return;

    btn.addEventListener('click', () => {
      const input = prompt(
        'Scale ingredients by factor (e.g. 2 or 3/2):',
        this.lastScaleInput
      );
      if (!input) return; // cancelled

      const factor = this.parseFactor(input);
      // only accept finite, positive numbers
      if (!(factor > 0 && isFinite(factor))) {
        alert(
          'Invalid scale. Please enter a positive number or fraction (e.g. "2" or "3/2"), and make sure denominator isn’t zero.'
        );
        return;
      }

      this.lastScaleInput = input;
      this.applyScale(input);
      this.updateScaleButtonLabel();
      this.saveRecipeState();
    });
  }

  applyScale(rawInput) {
    const factor = this.parseFactor(rawInput);

    document
      .querySelectorAll('li[data-quantity-value]')
      .forEach(li => {
        const orig = parseFloat(li.dataset.quantityValue);
        const unit = li.dataset.quantityUnit || '';
        const scaled = orig * factor;
        const pretty = Number.isInteger(scaled)
          ? scaled
          : Math.round(scaled * 100) / 100;
        const span = li.querySelector('.quantity');
        if (span) span.textContent = pretty + (unit ? ' ' + unit : '');
      });

    // Scale marked numbers (yield line + instruction numbers)
    document.querySelectorAll('.scalable[data-base-value]').forEach(span => {
      if (factor === 1) {
        span.textContent = span.dataset.originalText;
        span.classList.remove('scaled');
        span.removeAttribute('title');
      } else {
        const base = parseFloat(span.dataset.baseValue);
        const scaled = base * factor;
        const pretty = Number.isInteger(scaled)
          ? scaled
          : Math.round(scaled * 100) / 100;
        span.textContent = String(pretty);
        span.classList.add('scaled');
        span.title = 'Originally: ' + span.dataset.originalText;
      }
    });
  }

  updateScaleButtonLabel() {
    const btn = document.getElementById('scale-button');
    if (!btn) return;

    const factor = this.parseFactor(this.lastScaleInput);
    // only care about exactly 1 vs. anything else
    if (factor === 1) {
      btn.textContent = 'Scale';
    } else {
      const pretty = Number.isInteger(factor)
        ? factor
        : Math.round(factor * 100) / 100;
      btn.textContent = `Scale (x${pretty})`;
    }
  }

  parseFactor(str) {
    str = str.trim();
    const frac = str.match(/^(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)$/);
    if (frac) return parseFloat(frac[1]) / parseFloat(frac[2]);
    const num = parseFloat(str);
    return isNaN(num) ? NaN : num;
  }
}

// kick it all off
document.addEventListener('DOMContentLoaded', () => {
  new RecipeStateManager();
});