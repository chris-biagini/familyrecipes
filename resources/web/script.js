class RecipeStateManager {
  constructor() {
    // existing…
    this.recipeId = document.body.dataset.recipeId;
    this.versionHash = document.body.dataset.versionHash;
    this.STORED_STATE_TTL = 48 * 60 * 60 * 1000; // 48h

    this.crossableItemNodes = document.querySelectorAll(".ingredients li, .instructions p");
    this.sectionTogglerNodes = document.querySelectorAll("section h2");

    // NEW: track the last raw scale input
    this.lastScaleInput = '1';

    this.init();
  }

  init() {
    this.setupEventListeners();
    this.loadRecipeState();
    this.setupScaleButton();      // NEW: hook up the Scale button
  }

  saveRecipeState() {
    const currentRecipeState = {
      lastInteractionTime: Date.now(),
      versionHash: this.versionHash,
      crossableItemState: {},
      scaleFactor: this.lastScaleInput   // NEW: persist the raw input
    };

    this.crossableItemNodes.forEach((node, idx) => {
      currentRecipeState.crossableItemState[idx] = node.classList.contains("crossed-off");
    });

    localStorage.setItem(
      `saved-state-for-${this.recipeId}`,
      JSON.stringify(currentRecipeState)
    );
  }

  loadRecipeState() {
    const raw = localStorage.getItem(`saved-state-for-${this.recipeId}`);
    if (!raw) return console.log("No saved state found!");

    let stored;
    try {
      stored = JSON.parse(raw);
    } catch {
      console.log("Corrupt state JSON. Overwriting.");
      return this.saveRecipeState();
    }

    const { versionHash, lastInteractionTime, crossableItemState, scaleFactor } = stored;

    if (!versionHash || !lastInteractionTime || !crossableItemState) {
      console.log("Saved state invalid. Overwriting.");
      return this.saveRecipeState();
    }

    if (this.versionHash !== versionHash) {
      console.log("Version mismatch. Overwriting.");
      return this.saveRecipeState();
    }

    if (Date.now() - lastInteractionTime > this.STORED_STATE_TTL) {
      console.log("Saved state expired. Overwriting.");
      return this.saveRecipeState();
    }

    // re-apply cross‐off state
    this.crossableItemNodes.forEach((node, idx) => {
      if (crossableItemState[idx]) node.classList.add("crossed-off");
    });

    // NEW: re-apply scale
    if (scaleFactor) {
      this.lastScaleInput = scaleFactor;
      this.applyScale(scaleFactor);
    }

    console.log("Loaded and applied saved state.");
  }

  setupEventListeners() {
    // (no change to your cross-off logic)
    this.crossableItemNodes.forEach(node => {
      node.addEventListener("click", () => {
        node.classList.toggle("crossed-off");
        this.saveRecipeState();
      });
    });
    this.sectionTogglerNodes.forEach(h2 => {
      h2.addEventListener("click", () => {
        const section = h2.closest("section");
        const items = section.querySelectorAll(".ingredients li, .instructions p");
        const allCrossed = Array.from(items)
          .every(i => i.classList.contains("crossed-off"));
        items.forEach(i => i.classList.toggle("crossed-off", !allCrossed));
        this.saveRecipeState();
      });
    });
  }

  setupScaleButton() {
    const btn = document.getElementById("scale-button");
    if (!btn) return;

    btn.addEventListener("click", () => {
      const input = prompt(
        'Scale ingredients by factor (e.g. 2 or 3/2):',
        this.lastScaleInput
      );
      if (!input) return;

      const factor = parseFactor(input);
      if (!(factor > 0)) {
        alert('Couldn’t parse that. Try something like "2" or "3/2".');
        return;
      }

      this.lastScaleInput = input;
      this.applyScale(input);
      this.saveRecipeState();
    });
  }

  applyScale(rawInput) {
    const factor = parseFactor(rawInput);
    document.querySelectorAll("li[data-quantity-value]").forEach(li => {
      const orig = parseFloat(li.dataset.quantityValue);
      const unit = li.dataset.quantityUnit || "";
      const scaled = orig * factor;
      const pretty = Number.isInteger(scaled)
        ? scaled
        : Math.round(scaled * 100) / 100;
      const span = li.querySelector(".quantity");
      if (span) span.textContent = pretty + (unit ? " " + unit : "");
    });
  }
}

// global parseFactor stays as-is
function parseFactor(str) {
  str = str.trim();
  const frac = str.match(/^(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)$/);
  if (frac) return parseFloat(frac[1]) / parseFloat(frac[2]);
  const num = parseFloat(str);
  return isNaN(num) ? NaN : num;
}

document.addEventListener("DOMContentLoaded", () => {
  new RecipeStateManager();
});