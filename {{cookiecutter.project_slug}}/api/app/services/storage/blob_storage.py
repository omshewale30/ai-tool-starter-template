"""Azure Blob Storage wrapper (keyless / managed identity).

Thin convenience layer over `azure-storage-blob`. Authentication uses
DefaultAzureCredential — no account keys or connection strings are stored.

If `AZURE_STORAGE_ACCOUNT_URL` is unset (typical for local dev), the service is
considered disabled and calls raise a clear error instead of failing obscurely.
"""
from __future__ import annotations

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.core.logging import get_logger

logger = get_logger(__name__)


class BlobStorageService:
    def __init__(self, settings: Settings):
        self._settings = settings
        self._service_client = None

    @property
    def enabled(self) -> bool:
        return bool(self._settings.azure_storage_account_url)

    def _client(self):
        if not self.enabled:
            raise UpstreamServiceError("Blob storage is not configured (AZURE_STORAGE_ACCOUNT_URL)")
        if self._service_client is None:
            from azure.identity import DefaultAzureCredential
            from azure.storage.blob import BlobServiceClient

            self._service_client = BlobServiceClient(
                account_url=self._settings.azure_storage_account_url,
                credential=DefaultAzureCredential(),
            )
        return self._service_client

    def upload_bytes(self, blob_name: str, data: bytes, *, overwrite: bool = True) -> str:
        """Upload bytes to the configured container. Returns the blob URL."""
        container = self._settings.azure_storage_container
        blob = self._client().get_blob_client(container=container, blob=blob_name)
        blob.upload_blob(data, overwrite=overwrite)
        logger.info("Uploaded blob", extra={"container": container, "blob": blob_name})
        return blob.url

    def download_bytes(self, blob_name: str) -> bytes:
        container = self._settings.azure_storage_container
        blob = self._client().get_blob_client(container=container, blob=blob_name)
        return blob.download_blob().readall()
