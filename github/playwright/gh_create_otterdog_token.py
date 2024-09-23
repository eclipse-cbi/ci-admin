import sys
import common
import pyperclip
from playwright.sync_api import sync_playwright, expect


def setup_token(page, project_name):
    common.nav_to_token_settings(page)

    # Check if token has already been added
    page.get_by_role("heading", name="Personal access tokens (classic)").click() # This click is required, otherwise the next elements are not found!?
    if page.get_by_role("link", name="otterdog").is_visible():
        print("Otterdog token has been added already. Skipping.")
        return

    # Create Otterdog token
    page.get_by_role("button", name="Generate new token").click()
    page.get_by_role("menuitem", name="Generate new token (classic) For general use").click()
    page.get_by_label("Note").fill("otterdog")
    page.get_by_role("combobox", name="Expiration*").select_option("none")
    page.get_by_label("repo\n        \n\n        \n          \n            Full control of private repositories").check()
    page.get_by_label("workflow\n        \n\n        \n          \n            Update GitHub Action workflows").check()
    page.get_by_label("admin:org\n        \n\n        \n          \n            Full control of orgs and teams, read and write org projects").check()
    page.get_by_label("admin:org_hook\n        \n\n        \n          \n            Full control of organization hooks").check()
    page.get_by_label("delete_repo\n        \n\n        \n          \n            Delete repositories").check()
    page.get_by_role("button", name="Generate token").click()
    page.get_by_role("button", name="Copy token").click()

    # get token from clipboard
    otterdog_token = pyperclip.paste()
    print("otterdog_token: " + otterdog_token)
    # TODO: check that otterdog_token is not empty

    # add token to pass
    common.add_to_pass(project_name, otterdog_token, "otterdog-token")


def main():
    _DEFAULT_TIMEOUT = 10000

    if len(sys.argv) < 2:
        print("ERROR: project name must be set")
        sys.exit(1)
    else:
        project_name = sys.argv[1]
        print("Project name: " + project_name)

    print("opening browser window")
    with sync_playwright() as playwright:
        browser = playwright.firefox.launch(headless=False)
        context = browser.new_context(no_viewport=True)

        page = context.new_page()
        page.set_default_timeout(_DEFAULT_TIMEOUT)

        username = common.get_pass_creds(project_name, "username")
        password = common.get_pass_creds(project_name, "password")

        common.login(page, project_name, username, password)

        expect(page.get_by_role("heading", name="Home", exact=True)).to_be_visible(timeout=30000)

        setup_token(page, project_name)

        # input('Press any key to continue\n')
        common.signout(page)

        page.close()
        context.close()
        browser.close()


if __name__ == "__main__":
    main()
