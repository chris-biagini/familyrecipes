class RecipeProgressManager {
	constructor() {
		// set properties
		this.recipeId = document.body.dataset.recipeId || "defaultRecipe";
		this.TTL = 24 * 60 * 60 * 1000; // 24 hours

		this.crossableItemNodes = document.querySelectorAll(
			".ingredients li, .instructions p"
		);

		this.sectionHighlighterNodes = document.querySelectorAll("section h2");

		// Initialize
		this.init();
	}

	init() {
		this.setupEventListeners();
	}

	handleClickOnCrossableItem(crossableItemNode) {
		crossableItemNode.classList.toggle("crossed-off");
		console.log(crossableItemNode);
	}

	handleClickOnSectionHighlighterItem(sectionHighlighterNode) {
		sectionHighlighterNode.closest("section").classList.toggle("highlighted");
	}

	setupEventListeners() {
		this.crossableItemNodes.forEach((crossableItemNode) => {
			crossableItemNode.addEventListener("click", () => {
				this.handleClickOnCrossableItem(crossableItemNode);
			});
		});
		
		this.sectionHighlighterNodes.forEach((sectionHighlighterNode) => {
			sectionHighlighterNode.addEventListener("click", () => {
				this.handleClickOnSectionHighlighterItem(sectionHighlighterNode);
			});
		});
	}
}

document.addEventListener("DOMContentLoaded", function () {
	new RecipeProgressManager();
});
