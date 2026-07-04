# FIXTURE VULNERAVEL — coluna NOT NULL sem default.
from sqlalchemy import Column, String, Integer


class Order:
    id = Column(Integer, primary_key=True)
    snapshot = Column(String, nullable=False)
