class RecipeProgressManager {
	constructor() {
		// set properties
		this.recipeId = document.body.dataset.recipeId;
		this.versionHash = document.body.dataset.versionHash;
		this.STORED_STATE_TTL = 48 * (60 * 60 * 1000); // 48 hours in ms

		this.crossableItemNodes = document.querySelectorAll(".ingredients li, .instructions p");
		this.sectionTogglerNodes = document.querySelectorAll("section h2");

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
		currentRecipeState["versionHash"] = this.versionHash;
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
		const storedVersionHash = storedRecipeState["versionHash"];

		if (!storedCrossableItemState || !storedLastInteractionTime || !storedVersionHash) {
			console.log("Saved state appears to be invalid. Overwriting.");
			this.saveRecipeState();
			return;
		}

		if (this.versionHash != storedVersionHash) {
			console.log("Saved state is for a different version of this recipe. Overwriting.");
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

		this.sectionTogglerNodes.forEach((sectionTogglerNode) => {
			sectionTogglerNode.addEventListener("click", () => {
				const sectionToToggle = sectionTogglerNode.closest("section");

				const crossableItemsInSection = sectionToToggle.querySelectorAll(
					".ingredients li, .instructions p"
				);

				const allItemsInSectionAreCrossedOff = Array.from(crossableItemsInSection).every(
					(item) => item.classList.contains("crossed-off")
				);

				// if ALL li and p's are crossed off, then remove crossed-off from all and return
				if (allItemsInSectionAreCrossedOff) {
					crossableItemsInSection.forEach((item) => {
						item.classList.remove("crossed-off");
					});
				} else {
					// otherwise, apply crossed-off to all
					crossableItemsInSection.forEach((item) => {
						item.classList.add("crossed-off");
					});
				}

				this.saveRecipeState();
			});
		});
	}
}

document.addEventListener("DOMContentLoaded", function () {
	new RecipeProgressManager();
});
