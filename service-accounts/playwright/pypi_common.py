import os
import subprocess
import json

SITE = "pypi.org"
LOGIN_PAGE = "https://" + SITE + "/account/login"
REGISTER_PAGE = "https://" + SITE + "/account/register"

config_path = os.path.expanduser('~/.cbi/config')
with open(config_path, 'r') as config_file:
    config = json.load(config_file)

password_store_dir = config.get('password-store', {}).get('cbi-dir')
if password_store_dir:
    os.environ['PASSWORD_STORE_DIR'] = password_store_dir


def get_pass_2fa_otp(project_name):
    return os.popen("oathtool --totp -b $(pass bots/" + project_name + "/" + SITE + "/2FA-seed)").read()


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


def open_settings(page):
    if not page.get_by_text("Account settings").is_visible():
        page.get_by_label("View menu").click()
        page.get_by_role("link", name="Account settings").click()


def nav_to_token_settings(page):
     open_settings(page)
     # navigate to token settings
     page.get_by_role("link", name="Add API token").click()


def signout(page):
    page.get_by_label("View menu").click()
    page.get_by_role("button", name="Log out").click()


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
    page.get_by_placeholder("Your username").click()
    page.get_by_placeholder("Your username").fill(username)

    page.get_by_placeholder("Your password").click()
    page.get_by_placeholder("Your password").fill(password)

    page.get_by_role("button", name="Log in").click()

    #2FA
    if (page.get_by_role("heading", name="Two-factor authentication").is_visible()):
        twofa_token_pass = get_pass_2fa_otp(project_name)
        page.get_by_label("Enter authentication code (").click()
        page.get_by_label("Enter authentication code (").fill(twofa_token_pass)
        page.get_by_role("button", name="Verify").click()

