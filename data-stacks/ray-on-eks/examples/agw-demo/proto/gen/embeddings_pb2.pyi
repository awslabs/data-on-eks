from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class EmbedRequest(_message.Message):
    __slots__ = ("model", "texts")
    MODEL_FIELD_NUMBER: _ClassVar[int]
    TEXTS_FIELD_NUMBER: _ClassVar[int]
    model: str
    texts: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, model: _Optional[str] = ..., texts: _Optional[_Iterable[str]] = ...) -> None: ...

class Embedding(_message.Message):
    __slots__ = ("values",)
    VALUES_FIELD_NUMBER: _ClassVar[int]
    values: _containers.RepeatedScalarFieldContainer[float]
    def __init__(self, values: _Optional[_Iterable[float]] = ...) -> None: ...

class EmbedResponse(_message.Message):
    __slots__ = ("embeddings", "prompt_tokens", "model")
    EMBEDDINGS_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    embeddings: _containers.RepeatedCompositeFieldContainer[Embedding]
    prompt_tokens: int
    model: str
    def __init__(self, embeddings: _Optional[_Iterable[_Union[Embedding, _Mapping]]] = ..., prompt_tokens: _Optional[int] = ..., model: _Optional[str] = ...) -> None: ...
