class RecipeProgressManager {
	constructor() {
		// set properties
		this.recipeId = document.body.dataset.recipeId;
		this.STORED_STATE_TTL = 48 * (60 * 60 * 1000); // 48 hours in ms

		this.crossableItemNodes = document.querySelectorAll(".ingredients li, .instructions p");
		this.sectionHighlighterNodes = document.querySelectorAll("section h2");

		this.currentRecipeState = {};

		this.currentRecipeState["lastInteractionTime"] = 0;
		this.currentRecipeState["crossableItemState"] = {};

		// Initialize
		this.init();
	}

	init() {
		this.setupEventListeners();
		this.loadRecipeState();
	}

	saveRecipeState() {
		this.crossableItemNodes.forEach((crossableItemNode, index) => {
			this.currentRecipeState["crossableItemState"][index] =
				crossableItemNode.classList.contains("crossed-off");
		});

		this.currentRecipeState["lastInteractionTime"] = Date.now();

		localStorage.setItem(
			`saved-state-for-${this.recipeId}`,
			JSON.stringify(this.currentRecipeState)
		);
	}

	loadRecipeState() {
		const storedRecipeState = JSON.parse(
			localStorage.getItem(`saved-state-for-${this.recipeId}`)
		);

		if (!storedRecipeState) return;

		const storedCrossableItemState = storedRecipeState["crossableItemState"];
		const storedLastInteractionTime = storedRecipeState["lastInteractionTime"];

		const storedStateAge = Date.now() - storedLastInteractionTime;

		if (storedStateAge > this.STORED_STATE_TTL) {
			console.log("Saved state is too old (" + storedStateAge + " ms). Ignoring for now.");
			return;
		}

		this.crossableItemNodes.forEach((crossableItemNode, index) => {
			if (storedCrossableItemState[index] === true) {
				crossableItemNode.classList.add("crossed-off");
			}
		});
	}

	setupEventListeners() {
		this.crossableItemNodes.forEach((crossableItemNode) => {
			crossableItemNode.addEventListener("click", () => {
				crossableItemNode.classList.toggle("crossed-off");
				this.saveRecipeState();
			});
		});

		this.sectionHighlighterNodes.forEach((sectionHighlighterNode) => {
			sectionHighlighterNode.addEventListener("click", () => {
				sectionHighlighterNode.closest("section").classList.toggle("highlighted");

				// TODO: rename sectionHighlighterNodes to sectionTogglerNodes
				// if ALL li and p's are crossed off, then remove crossed-off from all and return
				// otherwise, apply crossed-off to all
			});
		});
	}
}

document.addEventListener("DOMContentLoaded", function () {
	new RecipeProgressManager();
});
