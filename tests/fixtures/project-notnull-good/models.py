# FIXTURE BOA — coluna NOT NULL com default.
from sqlalchemy import Column, String, Integer


class Order:
    id = Column(Integer, primary_key=True)
    snapshot = Column(String, nullable=False, server_default="")
