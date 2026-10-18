"""Add agendas table with ai_suggestion.

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-18
"""

import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "agendas",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), primary_key=True),
        sa.Column(
            "meeting_id",
            sa.Uuid(),
            sa.ForeignKey("meetings.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("items", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("action_items", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("ai_suggestion", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_agendas_meeting_id", "agendas", ["meeting_id"])


def downgrade() -> None:
    op.drop_index("ix_agendas_meeting_id", table_name="agendas")
    op.drop_table("agendas")
