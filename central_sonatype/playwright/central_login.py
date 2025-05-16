import sys
import common

from playwright.sync_api import sync_playwright, expect


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

        input('Press any key to continue\n')
        common.signout(page)

        page.close()
        context.close()
        browser.close()


if __name__ == "__main__":
    main()
