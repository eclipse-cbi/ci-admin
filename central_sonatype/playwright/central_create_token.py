import sys
import common
import pyperclip
from playwright.sync_api import sync_playwright, expect


def setup_token(page, project_name):
    common.nav_to_token_settings(page)

    token_name = "API-Token"

    # deal with existing token
    page.get_by_role("heading", name="Active Tokens", exact=True).click()
    if page.get_by_role("heading", name=token_name, exact=True).is_visible():
        print("Token '" + token_name + "' already exists. Skipping...")
        return

    print("Register token")
    page.locator("[data-test=\"refresh-btn\"]").click()
    page.get_by_label("Token Name").fill(token_name)

    page.get_by_text("Does not expire", exact=True).click()
    page.locator("[data-test=\"add-token-submit\"]").click()

    page.get_by_label("Copy Username", exact=True).click()
    token_username = pyperclip.paste()
    page.get_by_label("Copy Password").click()
    token_password = pyperclip.paste()

    print("Central token name: " + token_username)
    print("Central token pw: " + token_password)
    if token_username == "" or token_password == "":
        print("ERROR: central tokens are empty")
        sys.exit(1)

    # add token to pass
    common.add_to_pass(project_name, token_username, "token-username")
    common.add_to_pass(project_name, token_pass, "token-password")

    page.locator("[data-test=\"close-view-token-modal\"]").click()


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

        expect(page.get_by_role("link", name="Home", exact=True)).to_be_visible(timeout=30000)

        setup_token(page, project_name)

        # input('Press any key to continue\n')
        common.signout(page)

        page.close()
        context.close()
        browser.close()


if __name__ == "__main__":
    main()
