import sys
import os
import subprocess
import requests
import common
import pyperclip
from playwright.sync_api import sync_playwright, Error, expect


def signup(page, project_name, username, password, email):
    response = page.goto("https://github.com/signup")

    assert response is not None
    if not response.ok:
        raise RuntimeError(f"unable to load GitHub login page: {response.status}")

    expect(page.locator('#email')).to_be_visible(timeout=10000)
    page.locator('#email').fill(email)
    page.get_by_role("button", name="Continue").click()
    page.locator('#password').fill(password)
    page.get_by_role("button", name="Continue").click()
    page.locator("#login").fill(username)
    page.get_by_role("button", name="Continue").click()
    
    # EMail preferences (don't select check box)

    # little dance to get the "Continue" button to show up
    for x in range(10):
        if page.get_by_text("Receive occasional product").is_visible():
            page.wait_for_timeout(2000)
            page.get_by_label("Email preferences").uncheck()
            page.wait_for_timeout(2000)
            page.get_by_label("Email preferences").uncheck()
            page.get_by_role("button", name="Continue").click()
        else:
            print(x)
            break

    print("Please click on \"Verify\" button.")

    # MANUAL INTERVENTION
    # 1. Click on "Verify" button
    # 2. Solve Captcha
    # 3. Click on "Create account"
    # 4. Enter Launch code

    expect(page.get_by_role("heading", name="Sign in to GitHub")).to_be_visible(timeout=60000)

    # login page (new)
    if page.get_by_role("heading", name="Sign in to GitHub").is_visible():
        page.get_by_label("Username or email address").click()
        page.get_by_label("Username or email address").fill(username)
        page.get_by_label("Password").click()
        page.get_by_label("Password").fill(password)
        page.get_by_role("button", name="Sign in", exact=True).click()

    # 4. Skip personalization
    if page.get_by_role("link", name="Skip personalization").is_visible():
        page.get_by_role("link", name="Skip personalization").click()

    # TODO:
    # expect(page.get_by_text("Dashboard")).to_be_visible(timeout=30000)

    page.wait_for_timeout(2000)


def setup_2fa(page, project_name):
    home_dir = os.path.expanduser("~")
    downloads_dir = os.path.join(home_dir, "Downloads")

    # Navigate to 2FA settings
    common.open_settings(page)
    page.get_by_role("link", name="Password and authentication").click()

    # Check if 2FA is already enabled
    page.get_by_role("heading", name="Two-factor authentication", exact=True).click() # This click is required, otherwise the next elements are not found!?
    if not page.get_by_role("heading", name="Two-factor authentication is not enabled yet.").is_visible():
        print("2FA is already set up. Skipping.")
        return

    page.get_by_role("link", name="Enable two-factor authentication").click()
    page.get_by_role("button", name="setup key").click()

    # get 2FA seed text
    # TODO: is there a simpler and more reliable way??
    expect(page.get_by_role("dialog", name="Your two-factor secret")).to_be_visible()
    page.wait_for_timeout(2000)
    twofa_seed = page.locator('xpath=//div[@data-target="two-factor-setup-verification.mashedSecret"]').all_inner_texts()
    twofa_seed = ' '.join(twofa_seed)

    if not twofa_seed:
        page.page.get_by_role("dialog", name="Your two-factor secret").press("Escape")
        page.get_by_role("button", name="setup key").click()
        if not twofa_seed:
            sys.exit("2FA seed text not found!")

    print("Found 2FA seed text: " + twofa_seed)

    # input('Press any key to continue\n')

    # add 2FA seed to pass
    # os.popen("echo " + twofa_seed +" | pass insert bots/"+ project_name + "/github.com/2FA-seed").read()
    # os.popen("echo \"hello" + twofa_seed +"\"").read()
    subprocess.check_output("echo \"" + twofa_seed + "\" | pass insert -m bots/" + project_name + "/github.com/2FA-seed", shell=True)

    # get OTP from pass
    twofa_token = os.popen("oathtool --totp -b " + twofa_seed).read()
    print("2FA token: " + twofa_token)

    # enter OTP
    page.get_by_role("button", name="Close").click()
    page.get_by_role('textbox', name="Verify the code from the app").click()
    page.get_by_role('textbox', name="Verify the code from the app").fill(twofa_token)

    # get recovery codes
    page.locator(".two-factor-recovery-code").nth(0).text_content()  # The next line does not work without this one !?!??!
    twofa_codes = page.locator(".two-factor-recovery-code").all_text_contents()
    twofa_codes = '\n'.join(twofa_codes)

    print("Found 2FA recovery codes:\n" + twofa_codes)

    # input('Press any key to continue\n')

    # add 2FA codes to pass
    subprocess.check_output("echo \"" + twofa_codes + "\" | pass insert -m bots/" + project_name + "/github.com/2FA-recovery-codes", shell=True)

    # download recovery codes
    # FIXME
    with page.expect_download() as download_info:
        page.get_by_role("button", name="Download").click()
    download = download_info.value
    twofa_codes_files = os.path.join(downloads_dir, download.suggested_filename)
    print("Downloaded recovery codes to: " + twofa_codes_files)
    download.save_as(twofa_codes_files)

    # input('Press any key to continue\n')
    page.get_by_role("button", name="I have saved my recovery codes").click()
    page.get_by_role("button", name="Done").click()


def setup_ssh(page, project_name, ssh_pub_key, email):
    # navigate to SSH settings
    common.open_settings(page)
    page.get_by_role("link", name="SSH and GPG keys").click()

    # Check if SSH public key has already been added
    page.get_by_role("heading", name="SSH keys").click() # This click is required, otherwise the next elements are not found!?
    if page.get_by_role("heading", name="Authentication keys").is_visible():
        if page.get_by_text(email).is_visible():
            # Take screenshot
            page.screenshot(path="ssh_key_already_exists.png")
            print("SSH key has already been added. See screenshot.")
            return

    page.get_by_role("link", name="New SSH key").click()
    page.get_by_placeholder("Begins with 'ssh-rsa', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521', 'ssh-ed25519', 'sk-ecdsa-sha2-nistp256@openssh.com', or 'sk-ssh-ed25519@openssh.com'").fill(ssh_pub_key)
    page.get_by_role("button", name="Add SSH key").click()


def setup_token(page, project_name):
    short_name = common.get_project_shortname(project_name)

    common.nav_to_token_settings(page)

    # Check if token has already been added
    page.get_by_role("heading", name="Personal access tokens (classic)").click() # This click is required, otherwise the next elements are not found!?
    token_name = "Jenkins GitHub Plugin token https://ci.eclipse.org/" + short_name
    if page.get_by_role("link", name=token_name).is_visible():
        if common.ask_to_continue("Do you want to regenerate it? (yes/no):"):
            print("Regenerate jenkins token")

            # token list page
            page.get_by_role("link", name=token_name).click()
            page.get_by_role("link", name="Regenerate token").click()

            # Regenerate personal access token page
            page.get_by_role("button", name="30 days").click()
            page.get_by_role("menuitemradio", name="No expiration").click()
            page.get_by_role("button", name="Regenerate token").click()
            page.get_by_role("button", name="Copy token").click()

        else:
            return
    else:
        print("Create jenkins token")

        page.get_by_role("button", name="Generate new token").click()
        page.get_by_role("menuitem", name="Generate new token (classic) For general use").click()
        page.get_by_label("Note").fill(token_name)
        page.get_by_role("button", name="30 days").click()
        page.get_by_role("menuitemradio", name="No expiration").click()
        page.get_by_label("repo:status\n        \n\n        \n          \n            Access commit status").check()
        page.get_by_label("public_repo\n        \n\n        \n          \n            Access public repositories").check()
        page.get_by_label("admin:repo_hook\n        \n\n        \n          \n            Full control of repository hooks").check()
        page.get_by_label("admin:org_hook\n        \n\n        \n          \n            Full control of organization hooks").check()
        page.get_by_role("button", name="Generate token").click()
        page.get_by_role("button", name="Copy token").click()

    print("Register jenkins token")
    api_token = pyperclip.paste()
    print("API token: " + api_token)
    if not api_token:
        print("ERROR: jenkins token is empty")
        sys.exit(1)

    # add token to pass
    common.add_to_pass(project_name, api_token, "api-token")


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
        email = common.get_pass_creds(project_name, "email")
        ssh_pubkey = common.get_pass_creds(project_name, "id_rsa.pub")

        # check if GH account has been set up or not
        url = "https://github.com/" + username.strip()
        r = requests.head(url)
        print("Status Code for " + url + ": " + str(r.status_code))
        if r.status_code == 200:
            print("User account exists, trying to login.")
            common.login(page, project_name, username, password)
        else:
            print("User account does not exist, signing up.")
            signup(page, project_name, username, password, email)

        expect(page.get_by_role("heading", name="Home", exact=True)).to_be_visible(timeout=30000)

        setup_ssh(page, project_name, ssh_pubkey, email)
        setup_token(page, project_name)
        setup_2fa(page, project_name)

        # input('Press any key to continue\n')
        common.signout(page)

        page.close()
        context.close()
        browser.close()


if __name__ == "__main__":
    main()
