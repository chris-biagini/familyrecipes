class RecipeManager {
    constructor() {
        this.recipeId = document.body.dataset.recipeId || "defaultRecipe";
        this.EXPIRATION_TIME = 24 * 60 * 60 * 1000; // 24 hours
        
        // Storage keys
        this.keys = {
            lastInteraction: `lastInteractionTime_${this.recipeId}`,
            crossOff: `crossedOffIngredients_${this.recipeId}`,
            highlight: `highlightedSection_${this.recipeId}`
        };

        // Cache DOM elements
        this.sections = document.querySelectorAll("section");
        this.ingredientsContainers = document.querySelectorAll(".ingredients"); // Changed to querySelectorAll
        
        // Initialize
        this.init();
    }

    init() {
        // Check expiration before loading state
        if (this.hasExpired()) {
            this.clearAllState();
        } else {
            this.loadState();
        }

        this.setupEventListeners();
        this.updateInteractionTime();
    }

    // Storage Management with Error Handling
    getFromStorage(key, defaultValue = null) {
        try {
            const value = localStorage.getItem(this.keys[key]);
            return value ? JSON.parse(value) : defaultValue;
        } catch (e) {
            console.warn(`Error reading from storage (${key}):`, e);
            return defaultValue;
        }
    }

    saveToStorage(key, value) {
        try {
            localStorage.setItem(this.keys[key], JSON.stringify(value));
        } catch (e) {
            console.warn(`Error saving to storage (${key}):`, e);
        }
    }

    // Time Management
    updateInteractionTime() {
        this.saveToStorage('lastInteraction', Date.now());
    }

    hasExpired() {
        const lastTime = this.getFromStorage('lastInteraction', 0);
        return (Date.now() - lastTime) > this.EXPIRATION_TIME;
    }

    clearAllState() {
        Object.values(this.keys).forEach(key => {
            localStorage.removeItem(key);
        });
    }

    // State Management
    loadState() {
        this.loadCrossOffState();
        this.loadHighlightState();
    }

    loadHighlightState() {
        const highlightedIndex = this.getFromStorage('highlight');
        if (highlightedIndex !== null && this.sections[highlightedIndex]) {
            this.sections[highlightedIndex].classList.add('highlighted');
        }
    }

    // UI Updates with RequestAnimationFrame
    updateHighlight(section, index) {
        requestAnimationFrame(() => {
            this.removeAllHighlights();
            if (section) {
                section.classList.add('highlighted');
                this.saveToStorage('highlight', index);
            } else {
                this.saveToStorage('highlight', null);
            }
            this.updateInteractionTime();
        });
    }

    removeAllHighlights() {
        this.sections.forEach(sec => sec.classList.remove('highlighted'));
    }

    loadCrossOffState() {
        const crossedOffBitmap = this.getFromStorage('crossOff', '');
        if (crossedOffBitmap) {
            // Get all ingredient items across all sections
            const items = document.querySelectorAll('.ingredients ul > li');
            [...crossedOffBitmap].forEach((bit, index) => {
                if (bit === '1' && items[index]) {
                    items[index].classList.add('crossed-off');
                }
            });
        }
    }

    saveCrossOffState() {
        // Get all ingredient items across all sections
        const items = document.querySelectorAll('.ingredients ul > li');
        const bitmap = Array.from(items)
            .map(li => li.classList.contains('crossed-off') ? '1' : '0')
            .join('');
        this.saveToStorage('crossOff', bitmap);
        this.updateInteractionTime();
    }

    // ... (other methods remain the same until setupEventListeners)

    setupEventListeners() {
        // Event delegation for ingredients - now at the document level
        document.addEventListener('click', (event) => {
            const li = event.target.closest('li');
            if (li && li.closest('.ingredients ul')) {
                event.stopPropagation();
                li.classList.toggle('crossed-off');
                this.saveCrossOffState();
            }
        });

        // Event delegation for sections
        document.addEventListener('click', (event) => {
            // Clear highlight when clicking outside sections
            if (!event.target.closest('section')) {
                this.updateHighlight(null);
                return;
            }

            const section = event.target.closest('section');
            if (!section) return;

            // Don't highlight if clicking in ingredients area
            if (event.target.closest('.ingredients')) return;

            event.stopPropagation();
            const index = Array.from(this.sections).indexOf(section);
            const wasHighlighted = section.classList.contains('highlighted');
            
            this.updateHighlight(wasHighlighted ? null : section, index);
        });
    }
}

document.addEventListener("DOMContentLoaded", function() {
    // Initialize the recipe manager
    new RecipeManager();
});