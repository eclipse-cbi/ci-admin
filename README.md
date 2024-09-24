# CI Admin

This repo contains scripts to adminstrate the CI infrastructure at the Eclipse Foundation.

Most scripts will not work without access to the password store or the internal network.

## Dependencies

* [bash 4](https://www.gnu.org/software/bash/)
* [curl](https://curl.se/)
* [docker](https://www.docker.com)
* [git](https://git-scm.com)
* [jq](https://stedolan.github.io/jq/)
* [pass](https://www.passwordstore.org)


## playwright installation

```shell
sudo apt install oathtool
sudo apt install python-is-python3
python -m pip install --upgrade pip
python -m pip install playwright 
python -m pip install pyperclip
playwright install
```