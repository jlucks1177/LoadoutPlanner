# Publishing LoadoutPlanner

Once this is set up, **every morning** a GitHub Action fetches the most-played talent builds, puts them **inside** the addon, and, if they changed, publishes a new version to GitHub, CurseForge and Wago. Players just install LoadoutPlanner from their addon manager: no Node.js, no API key, no setup.

Time needed: about 45 minutes, most of it creating accounts. You need a **GitHub** account. **CurseForge** and **Wago** are optional but are where players find addons (the CurseForge app alone covers most players).

---

## Part A: GitHub (required)

### A1. Create the repository

1. Go to **https://github.com/new**.
2. **Repository name:** `LoadoutPlanner`
3. Choose **Public**. Scheduled jobs are free and unlimited on public repositories, and addon sites like to link to the source.
4. **Don't** tick "Add a README" (the project already has one).
5. Click **Create repository**. Leave the page open; you need its URL in the next step.

### A2. Upload the project

Unzip **LoadoutPlanner-repo.zip**. In a terminal, in the unzipped `LoadoutPlanner-repo` folder, run these commands, replacing `YOUR-NAME` with your GitHub username:

```
git init
git add -A
git commit -m "LoadoutPlanner 0.17.0"
git branch -M main
git remote add origin https://github.com/YOUR-NAME/LoadoutPlanner.git
git push -u origin main
```

If Git asks you to sign in, use your GitHub account (a browser window may open).

### A3. Let the workflows publish

1. In your repository: **Settings → Actions → General**.
2. Scroll to **Workflow permissions**, choose **Read and write permissions**, and click **Save**.

Without this, the Action can't save the new builds or create releases ("Resource not accessible by integration").

**Stop here if you only want GitHub releases for now.** Skip to Part D to run it. You can come back for CurseForge and Wago any time.

---

## Part B: CurseForge (recommended: most players use the CurseForge app)

### B1. Create the project

1. Go to **https://authors.curseforge.com** and sign in (or create an account).
2. **Create project → World of Warcraft → Addon.**
3. Fill in:
   - **Name:** LoadoutPlanner
   - **Summary:** "Tag talent builds to raids, bosses and dungeons, get prompted to switch on entry, and browse the most-played builds for your spec."
   - **Description:** you can paste the top part of `README.md`.
   - **Category:** Class, and any talent-related category offered.
   - **License:** your choice (MIT is common for addons).
4. Save. Find the **Project ID**, a number shown in the project's "About" box, e.g. `1234567`. Write it down.

### B2. Create an upload token

1. Go to **https://authors.curseforge.com/#/settings/api-tokens**.
2. Create a token (name it "LoadoutPlanner GitHub"). **Copy it now**, because it's only shown once.

### B3. Give them to GitHub

In your repository: **Settings → Secrets and variables → Actions**.

1. **Secrets** tab → **New repository secret**:
   - Name: `CF_API_KEY`
   - Secret: the token from B2
2. **Variables** tab → **New repository variable**:
   - Name: `CURSEFORGE_PROJECT_ID`
   - Value: the number from B1

Note: CurseForge moderators review a new project's **first file** before it's public. That can take a day or two. Later files usually go through automatically.

---

## Part C: Wago (optional)

1. Go to **https://addons.wago.io**, sign in, and open the **Developer** dashboard.
2. Create a project for LoadoutPlanner. Its **project ID** (8 characters, e.g. `aB3dE5fG`) is shown on the dashboard.
3. Create an API key at **https://addons.wago.io/account/apikeys**.
4. In GitHub, **Settings → Secrets and variables → Actions**:
   - Secret `WAGO_API_TOKEN` = the key
   - Variable `WAGO_PROJECT_ID` = the project ID

---

## Part D: Run it for the first time

1. In your repository, open the **Actions** tab. If GitHub asks, click **"I understand my workflows, go ahead and enable them"**.
2. Click **Daily builds** on the left, then **Run workflow → Run workflow**.
3. Wait about 2 minutes. A green check means it worked.
4. Open the repository's **Releases** (right side of the main page). You'll see a release named like `v0.17.0.20260927` with `LoadoutPlanner-v0.17.0.20260927.zip`.
5. If you set up Part B or C, the same version appears on CurseForge (after review) and Wago.

**Check it in game:** install that zip (or update through your addon manager), `/reload`, open talents → **Top builds**. The header should say *"Most-played builds from parses.gg logs, Midnight Season 2. Built in, updated today."*

From now on it runs every morning at 6:17 AM Central, and publishes only on days when the builds changed.

---

## Part E: Adding Raider.IO builds (after asking permission)

Personal use of Raider.IO's API is fine, but publishing its data to every player is redistribution, so ask first. You can message them through Raider.IO's Discord or their addon's GitHub, for example:

> Hi! I'm the author of LoadoutPlanner, a WoW talent loadout addon. I'd like to include the most-played talent builds per dungeon and raid boss, computed daily from your public API (Mythic+ leaderboard rosters and top guilds' boss-kill rosters: aggregated counts plus the talent strings, no player names), bundled in the addon with attribution to Raider.IO. It makes about 400 API requests a day with an application key, at one request per second. Would that be OK with you, and is there any attribution you'd like?

**If they say yes:**

1. Create a Raider.IO application key (raider.io → account settings → API / applications).
2. GitHub → **Settings → Secrets and variables → Actions**:
   - Secret `RAIDERIO_API_KEY` = the key
   - Variable `INCLUDE_RAIDERIO` = `true`
3. Run **Daily builds** by hand once (Part D). The **Raider.IO** source then works for every player too.

---

## Everyday use

**Releasing your own code changes:**

1. `git pull`, change the addon, run the tests (`lua tools/test/run.lua`), and test it in game.
2. Put the new version number in the `VERSION` file (e.g. `0.18.0`).
3. Commit, tag, push:

```
git add -A
git commit -m "What changed"
git push
git tag -a v0.18.0 -m "v0.18.0"
git push origin v0.18.0
```

The **Release** workflow publishes it. Daily data releases then continue as `v0.18.0.YYYYMMDD`.

**If a daily run fails:** GitHub emails you. Open the run in the Actions tab, and the red step shows why. Common causes:

- **"returned no builds at all"**: parses.gg was down or changed its format. Nothing was published and players keep the previous builds. It retries tomorrow.
- **"Resource not accessible by integration"**: redo A3.
- **A CurseForge or Wago upload error**: check the token and project ID for that site (Parts B and C).

**Good to know:** GitHub pauses scheduled workflows in a repository with no activity for 60 days. The daily data commits count as activity whenever builds change, but after a long quiet spell (like between seasons), check the Actions tab and click **Enable workflow** if it's been paused.
