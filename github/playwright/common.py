import os
import subprocess
import json

SITE = "github.com"
LOGIN_PAGE = "https://" + SITE + "/login"

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
            #print("Continuing...")
            return True
        elif user_input in ['no', 'n']:
            #print("Exiting...")
            return False
        else:
            print("Please enter 'yes/y' or 'no/n'.")


def open_nav_menu(page):
    page.get_by_label("Open user navigation menu").click()


def open_settings(page):
    # FIXME this is not perfect since it seems to be true even on the Settings/Developer Settings page
    # if not page.get_by_role("link", name="Settings", exact=True).is_visible():
    if not page.get_by_text("Your personal account").is_visible():
        open_nav_menu(page)
        page.get_by_label("Settings", exact=True).click()


def nav_to_token_settings(page):
    open_settings(page)
    # navigate to token settings
    page.get_by_role("link", name="Developer settings").click()
    page.get_by_role("button", name="Personal access tokens").click()
    page.get_by_role("link", name="Tokens (classic)").click()


def signout(page):
    open_nav_menu(page)
    page.get_by_role("link", name="Sign out").click()
    page.get_by_role("button", name="Sign out from all accounts", exact=True).click()


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
    page.get_by_label("Username or email address").click()
    page.get_by_label("Username or email address").fill(username)

    page.get_by_label("Password").click()
    page.get_by_label("Password").fill(password)

    page.get_by_role("button", name="Sign in", exact=True).click()

    if (page.get_by_role("heading", name="Device verification").is_visible()):
        print("Found device verification page.")
        # manual task
        print("Waiting for verification code...")
        # input('Press any key to continue\n')
        # TODO: wait for page element instead
    elif (page.get_by_role("heading", name="Two-factor authentication").is_visible()):
        print("Found token verification page.")
        twofa_token_pass = get_pass_2fa_otp(project_name)
        page.get_by_placeholder("XXXXXX").click()
        page.get_by_placeholder("XXXXXX").fill(twofa_token_pass)
    else:
        print("Device verification page not found or skipped.")
    
    # deal with confirm account settings page
    if (page.get_by_text("Confirm your account recovery settings").is_visible()):
        print("Found account confirmation page.")
        page.get_by_role("button", name="Confirm").click()

    # add wait before continuing for secondary 2FA
    page.wait_for_timeout(2000)

    if (page.get_by_role("heading", name="Two-factor authentication").is_visible()):
        print("Found 2nd token verification page.")
        print("Waiting for next 2FA token for 35 seconds...")
        page.wait_for_timeout(35000)
        twofa_token_pass = get_pass_2fa_otp(project_name)
        page.get_by_role("button", name="Verify 2FA now").click()
        #Page title "Verify your two-factor authentication (2FA) settings"
        page.get_by_placeholder("XXXXXX").fill(twofa_token_pass)
        page.get_by_role("button", name="Verify").click()

    if (page.get_by_role("heading", name="2FA verification successful!").is_visible()):
        page.get_by_role("link", name="Done").click()

    print("")
