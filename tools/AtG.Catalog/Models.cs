namespace AtG.Catalog;

public sealed record SourceOccurrenceInput(
    string SourceFile,
    string Kind,
    string Original,
    string Translation,
    string Status,
    string ReviewState,
    string ReasonCode,
    string Safety,
    string Notes,
    string Locators);

public sealed record SourceOccurrence(
    long Id,
    long SemanticGroupId,
    string SourceFile,
    string Kind,
    string Original,
    string Translation,
    string Status,
    string ReviewState,
    string ReasonCode,
    string Safety,
    string Notes,
    string Locators);

public sealed record TranslationBindingInput(
    long SemanticGroupId,
    string Translation,
    string Status,
    string Safety,
    string PatchMethod,
    string Notes);

public sealed record TranslationBinding(
    long Id,
    long SemanticGroupId,
    string Translation,
    string Status,
    string Safety,
    string PatchMethod,
    string Notes);

public sealed record EvidenceInput(
    long? SemanticGroupId,
    long? SourceOccurrenceId,
    string Kind,
    string Reference,
    string Details);

public sealed record Evidence(
    long Id,
    long? SemanticGroupId,
    long? SourceOccurrenceId,
    string Kind,
    string Reference,
    string Details,
    string CreatedUtc);

public sealed record ImportResult(long ImportedOccurrences, long SemanticGroups);
