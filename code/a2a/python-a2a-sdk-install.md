## Agent 1
#### Create a directory
```
mkdir server
cd server
```

#### Initialize your Python env
```
uv init

uv venv --python 3.13
source .venv/bin/activate
```

#### Install the A2A SDK
```
uv add uvicorn "a2a-sdk[all]" --python 3.13
```

#### Make sure they are all installed
```
python3 --version
python3 -c "import a2a; print('A2A SDK imported successfully')"
uv pip freeze | grep a2a
```



## Agent 2
#### Create a directory
```
mkdir client
cd client
```

#### Initialize your Python env
```
uv init

uv venv --python 3.13
source .venv/bin/activate
```

#### Install the A2A SDK
```
uv add httpx "a2a-sdk[all]" --python 3.13
```

#### Make sure they are all installed
```
python3 --version
python3 -c "import a2a; print('A2A SDK imported successfully')"
uv pip freeze | grep a2a
```
