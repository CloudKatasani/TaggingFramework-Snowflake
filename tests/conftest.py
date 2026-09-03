import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "scripts"))

import catalog as C  # noqa: E402


@pytest.fixture(scope="session")
def cat():
    return C.load()


@pytest.fixture(scope="session")
def by_name(cat):
    return C.tag_by_name(cat)
