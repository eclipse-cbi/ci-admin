import os
import subprocess
import json

SITE = "central.sonatype.org"
AUTH_SITE = "central.sonatype.com"
LOGIN_PAGE = "https://" + AUTH_SITE + "/api/auth/login"

config_path = os.path.expanduser('~/.cbi/config')
with open(config_path, 'r') as config_file:
    config = json.load(config_file)

password_store_dir = config.get('password-store', {}).get('cbi-dir')
if password_store_dir:
    os.environ['PASSWORD_STORE_DIR'] = password_store_dir

def get_pass_creds(project_name, item):
    return os.popen("pass bots/" + project_name + "/" + SITE + "/" + item).read()

def add_to_pass(project_name, item, item_name):
    subprocess.check_output("echo \"" + item + "\" | pass insert -m bots/" + project_name + "/" + SITE + "/" + item_name, shell=True)


def get_project_shortname(project_name):
    # TODO: can this be simplified?
    if project_name.find("."):
        short_name = "".join(project_name.split(".")[-1:])
    else:
        short_name = "".join(project_name)
    return short_name


def ask_to_continue(message="Do you want to continue? (yes/no): "):
    while True:
        user_input = input(message).strip().lower()
        if user_input in ['yes', 'y']:
            print("Continuing...")
            return True
        elif user_input in ['no', 'n']:
            print("Exiting...")
            return False
        else:
            print("Please enter 'yes' or 'no'.")


def open_nav_menu(page):
    page.get_by_role("button", name="Avatar").click()


def nav_to_token_settings(page):
    open_nav_menu(page)
    page.get_by_role("link", name="View User Tokens").click()


def signout(page):
    open_nav_menu(page)
    page.locator('[data-test="header-dropdown"]').get_by_role("link", name="Sign out", exact=True).click()


def login(page, project_name, username, password):
    response = page.goto(LOGIN_PAGE)

    assert response is not None
    if not response.ok:
        raise RuntimeError(f"unable to load " + SITE + " login page: {response.status}")

    print("Login page loaded.")
    print("Username: " + username)

    if username is None or password is None or username == "" or password == "":
        raise RuntimeError("Username or password not set.")

    # login
    page.get_by_role("textbox", name="Username or email address").click()
    page.get_by_role("textbox", name="Username or email address").fill(username)

    page.get_by_role("textbox", name="Password").click()
    page.get_by_role("textbox", name="Password").fill(password)

    page.get_by_role("button", name="Continue", exact=True).click()
