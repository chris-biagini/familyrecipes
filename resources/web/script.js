class RecipeProgressManager {
	constructor() {
		// set properties
		this.recipeId = document.body.dataset.recipeId;
		//this.storedStateTimeToLive = 48 * (60 * 60 * 1000); // 48 hours in ms
		this.storedStateTimeToLive = 20 * 1000; // 20 seconds in ms

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
		const currentCrossableItemState = {};

		this.crossableItemNodes.forEach((crossableItemNode, index) => {
			currentCrossableItemState[index] = crossableItemNode.classList.contains("crossed-off");
		});

		currentRecipeState["crossableItemState"] = currentCrossableItemState;
		currentRecipeState["lastInteractionTime"] = Date.now();

		localStorage.setItem(
			`saved-state-for-${this.recipeId}`,
			JSON.stringify(currentRecipeState)
		);
	}

	loadRecipeState() {
		const storedRecipeState = JSON.parse(
			localStorage.getItem(`saved-state-for-${this.recipeId}`)
		);

		if (!storedRecipeState) return;

		const storedCrossableItemState = storedRecipeState["crossableItemState"];

		const storedLastInteractionTime = storedRecipeState["lastInteractionTime"];

		const stateAge = Date.now() - storedLastInteractionTime;

		if (stateAge > this.storedStateTimeToLive) {
			console.log("Saved state is too old (" + stateAge + " ms). Ignoring for now.");
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
			});
		});
	}
}

document.addEventListener("DOMContentLoaded", function () {
	new RecipeProgressManager();
});
