import os
import shutil
import subprocess
import tempfile
from html.parser import HTMLParser
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CLI_DIR = REPO_ROOT / "cli"
VIEWY = CLI_DIR / ("viewy.exe" if os.name == "nt" else "viewy")
TEMPLATES = ("react", "svelte")


class ExternalAssetParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "script" and attrs.get("src"):
            self.refs.append(f"script src={attrs['src']}")
        if (
            tag == "link"
            and attrs.get("rel", "").lower() == "stylesheet"
            and attrs.get("href")
        ):
            self.refs.append(f"stylesheet href={attrs['href']}")


def run(args, *, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)


def assert_self_contained_index(app_dir):
    dist = app_dir / "dist"
    index = dist / "index.html"
    if not index.is_file():
        raise AssertionError("frontend build did not produce dist/index.html")
    dist_files = sorted(path.relative_to(dist) for path in dist.rglob("*") if path.is_file())
    if dist_files != [Path("index.html")]:
        files = ", ".join(str(path) for path in dist_files)
        raise AssertionError(f"frontend build produced multiple dist files: {files}")

    parser = ExternalAssetParser()
    parser.feed(index.read_text(encoding="utf-8"))
    if parser.refs:
        refs = ", ".join(parser.refs)
        raise AssertionError(f"dist/index.html references external assets: {refs}")


def build_template(template, tmpdir):
    app = f"viewy-{template}-ci"
    env = os.environ.copy()
    env["VIEWY_TEMPLATE_ROOT"] = str(CLI_DIR / "src" / "viewy_cli" / "templates")
    env["VIEWY_LIB_SRC"] = str(REPO_ROOT)

    run([str(VIEWY), "init", app, "--template", template], cwd=tmpdir, env=env)
    app_dir = tmpdir / app
    run(["npm", "ci"], cwd=app_dir)
    run(["npm", "run", "build"], cwd=app_dir)
    assert_self_contained_index(app_dir)
    run([str(VIEWY), "build", "--release"], cwd=app_dir, env=env)


def main():
    run(["nimble", "build", "-y"], cwd=CLI_DIR)

    tmpdir = Path(tempfile.mkdtemp(prefix="viewy-template-ci-"))
    try:
        for template in TEMPLATES:
            build_template(template, tmpdir)
    finally:
        shutil.rmtree(tmpdir)


if __name__ == "__main__":
    main()
