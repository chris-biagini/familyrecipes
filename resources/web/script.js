class RecipeProgressManager {
	constructor() {
		// set properties
		this.recipeId = document.body.dataset.recipeId || "defaultRecipe";
		this.TTL = 24 * 60 * 60 * 1000; // 24 hours

		this.crossableItems = document.querySelectorAll(
			".ingredients li, .instructions p"
		);

		this.sectionHighlighterItems = document.querySelectorAll("section h2");

		// Initialize
		this.init();
	}

	init() {
		this.setupEventListeners();
	}

	handleClickOnCrossableItem(crossableItem) {
		crossableItem.classList.toggle("crossed-off");
	}

	handleClickOnSectionHighlighterItem(sectionHighlighterItem) {
		sectionHighlighterItem.closest("section").classList.toggle("highlighted");
	}

	setupEventListeners() {
		this.crossableItems.forEach((crossableItem) => {
			crossableItem.addEventListener("click", () => {
				this.handleClickOnCrossableItem(crossableItem);
			});
		});
		
		this.sectionHighlighterItems.forEach((sectionHighlighterItem) => {
			sectionHighlighterItem.addEventListener("click", () => {
				this.handleClickOnSectionHighlighterItem(sectionHighlighterItem);
			});
		});
	}
}

document.addEventListener("DOMContentLoaded", function () {
	new RecipeProgressManager();
});
