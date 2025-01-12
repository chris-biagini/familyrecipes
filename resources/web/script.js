class RecipeProgressManager {
	constructor() {
		// set properties
		this.recipeId = document.body.dataset.recipeId;
		this.STORED_STATE_TTL = 48 * (60 * 60 * 1000); // 48 hours in ms

		this.crossableItemNodes = document.querySelectorAll(".ingredients li, .instructions p");
		this.sectionHighlighterNodes = document.querySelectorAll("section h2");

		// Initialize
		this.init();
	}

	init() {
		this.setupEventListeners();
		this.loadRecipeState();
	}

	saveRecipeState() {
		const currentRecipeState = {};
		currentRecipeState["lastInteractionTime"] = Date.now();
		currentRecipeState["crossableItemState"] = {};

		this.crossableItemNodes.forEach((crossableItemNode, index) => {
			currentRecipeState["crossableItemState"][index] =
				crossableItemNode.classList.contains("crossed-off");
		});

		localStorage.setItem(
			`saved-state-for-${this.recipeId}`,
			JSON.stringify(currentRecipeState)
		);
	}

	loadRecipeState() {
		const storedRecipeState = JSON.parse(
			localStorage.getItem(`saved-state-for-${this.recipeId}`)
		);

		if (!storedRecipeState) {
			console.log("No saved state found!");
			return;
		}

		const storedCrossableItemState = storedRecipeState["crossableItemState"];
		const storedLastInteractionTime = storedRecipeState["lastInteractionTime"];

		if (!storedCrossableItemState || !storedLastInteractionTime) {
			console.log("Saved state appears to be invalid. Overwriting.");
			this.saveRecipeState();
			return;
		}

		const storedStateAge = Date.now() - storedLastInteractionTime;

		if (storedStateAge > this.STORED_STATE_TTL) {
			console.log("Saved state is too old (" + storedStateAge + " ms). Overwriting.");
			this.saveRecipeState();
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
