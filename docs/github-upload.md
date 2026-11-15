# Putting Rerun on GitHub (no installs needed)

## First upload

1. Sign in at **github.com**. Click **+** (top right) → **New repository**.
2. Name it (for example `rerun`), choose **Private**, and leave "Add a README" **unticked**. Click **Create repository**.
3. On the empty repository page, click the link **uploading an existing file**.
4. Open the project folder in File Explorer. Select these items and drag them into the browser window:
   - `README.md`
   - `.gitignore`
   - the folders `src`, `web`, `ios`, `docs`, `tools`

   Don't upload the `.claude` folder; it only holds local settings for this editor. Chrome and Edge keep the folder structure when you drag folders in.
5. Type a short message such as "First version" and click **Commit changes**.

## Let your brother download it

Because the repository is private, add him as a collaborator:

1. In the repository, open **Settings** → **Collaborators** → **Add people**.
2. Enter his GitHub username or email and send the invite.
3. Once he accepts, he can click **Code** → **Download ZIP**, or clone it with Git on his Mac.

## Uploading changes later

1. Open the repository, click **Add file** → **Upload files**.
2. Drag in the changed files or folders. Files with the same path are replaced.
3. Commit the changes.

After changing the game, remember to rebuild `web/index.html` first (see the README) so the app picks up the change.
