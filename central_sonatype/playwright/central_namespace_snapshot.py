import sys
import common
from playwright.sync_api import sync_playwright, expect


def check(page, project_name):
    page.get_by_role('link', name='Publish').wait_for()

    try:
        page.get_by_role('link', name='Publish').click()
    except:
        print(f"{project_name}: No publisher ⚠️")
        return

    page.locator('[data-test="namespace-tab"]').click()
    page.wait_for_timeout(2000)

    namespace_items = page.locator("[data-test=\"namespace-item\"]")
    item_count = namespace_items.count()

    if item_count > 0:
        print(f"{project_name}: Found {item_count} namespace(s)")

        for i in range(item_count):
            try:
                namespace_item = namespace_items.nth(i)
                namespace_text = namespace_item.inner_text()
                has_snapshot = namespace_item.locator("div", has_text="SNAPSHOTs enabled").count() > 0

                if has_snapshot:
                    print(f"namespace {namespace_text} : snapshot already activated. Skip.")
                    continue

                print(f"{project_name}: Activate snapshot for namespace {namespace_text}")

                more_actions_button = namespace_item.get_by_role("button", name="More Actions...")
                more_actions_button.click()
                page.locator("[data-test=\"enable-snapshot-btn\"]").click()
                page.locator("[data-test=\"confirm-btn\"]").click()
                page.keyboard.press("Escape")
                page.wait_for_timeout(1000)

            except Exception as e:
                print(f"{project_name}: Snapshot Failed! ({e})")

    else:
        print(f"{project_name}: No namespace found")


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

        try:        
            expect(page.get_by_role("link", name="Home", exact=True)).to_be_visible(timeout=2000)
        except:
            print(project_name + ": Login failed ❌")
            return
        check(page, project_name)

        common.signout(page)

        page.close()
        context.close()
        browser.close()


if __name__ == "__main__":
    main()
