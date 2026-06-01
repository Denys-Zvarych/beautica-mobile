// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serializers.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers = (Serializers().toBuilder()
      ..add(ApiResponseAuthResponse.serializer)
      ..add(ApiResponseAvailableSlotsResponse.serializer)
      ..add(ApiResponseAvatarResponse.serializer)
      ..add(ApiResponseBookingDetailResponse.serializer)
      ..add(ApiResponseBookingResponse.serializer)
      ..add(ApiResponseCategoryRequestResponse.serializer)
      ..add(ApiResponseInvitePreviewResponse.serializer)
      ..add(ApiResponseInviteResponse.serializer)
      ..add(ApiResponseListApprovedCategoryResponse.serializer)
      ..add(ApiResponseListCatalogCategoryResponse.serializer)
      ..add(ApiResponseListCityDistrictResponse.serializer)
      ..add(ApiResponseListCityResponse.serializer)
      ..add(ApiResponseListMasterServiceResponse.serializer)
      ..add(ApiResponseListOblastResponse.serializer)
      ..add(ApiResponseListPlatformCategoryUsageResponse.serializer)
      ..add(ApiResponseListSalonResponse.serializer)
      ..add(ApiResponseListServiceTypeResponse.serializer)
      ..add(ApiResponseListWorkingHoursResponse.serializer)
      ..add(ApiResponseMasterDetailResponse.serializer)
      ..add(ApiResponseMasterPublicProfileResponse.serializer)
      ..add(ApiResponseMasterServiceResponse.serializer)
      ..add(ApiResponseMediaFileResponse.serializer)
      ..add(ApiResponsePageMediaFileResponse.serializer)
      ..add(ApiResponsePageResponseBookingResponse.serializer)
      ..add(ApiResponsePageResponseMasterSearchResult.serializer)
      ..add(ApiResponsePageResponseMasterSummaryResponse.serializer)
      ..add(ApiResponsePageResponseReviewResponse.serializer)
      ..add(ApiResponsePageResponseSalonSearchResult.serializer)
      ..add(ApiResponsePlatformCategoryResponse.serializer)
      ..add(ApiResponsePublicSalonResponse.serializer)
      ..add(ApiResponseRegistrationResponse.serializer)
      ..add(ApiResponseRevenueResponse.serializer)
      ..add(ApiResponseReviewResponse.serializer)
      ..add(ApiResponseSalonResponse.serializer)
      ..add(ApiResponseServiceDefinitionResponse.serializer)
      ..add(ApiResponseUserProfileResponse.serializer)
      ..add(ApiResponseVoid.serializer)
      ..add(ApprovedCategoryResponse.serializer)
      ..add(AssignServiceToMasterRequest.serializer)
      ..add(AuthResponse.serializer)
      ..add(AuthResponseRoleEnum.serializer)
      ..add(AvailableSlotResponse.serializer)
      ..add(AvailableSlotsResponse.serializer)
      ..add(AvatarResponse.serializer)
      ..add(BookingDetailResponse.serializer)
      ..add(BookingDetailResponseStatusEnum.serializer)
      ..add(BookingResponse.serializer)
      ..add(BookingResponseStatusEnum.serializer)
      ..add(CancelBookingRequest.serializer)
      ..add(CancelBookingRequestCancellationReasonEnum.serializer)
      ..add(CatalogCategoryResponse.serializer)
      ..add(CategoryRequestResponse.serializer)
      ..add(CityDistrictResponse.serializer)
      ..add(CityResponse.serializer)
      ..add(CreateBookingRequest.serializer)
      ..add(CreateCategoryRequestRequest.serializer)
      ..add(CreatePlatformCategoryRequest.serializer)
      ..add(CreateReviewRequest.serializer)
      ..add(CreateSalonRequest.serializer)
      ..add(CreateServiceDefinitionRequest.serializer)
      ..add(ForgotPasswordRequest.serializer)
      ..add(IndependentMasterUpdateRequest.serializer)
      ..add(InviteAcceptRequest.serializer)
      ..add(InvitePreviewResponse.serializer)
      ..add(InvitePreviewResponseRoleEnum.serializer)
      ..add(InviteRequest.serializer)
      ..add(InviteRequestRoleEnum.serializer)
      ..add(InviteResponse.serializer)
      ..add(LocationFilter.serializer)
      ..add(LoginRequest.serializer)
      ..add(MasterDetailResponse.serializer)
      ..add(MasterDetailResponseMasterTypeEnum.serializer)
      ..add(MasterProfileUpdateRequest.serializer)
      ..add(MasterPublicProfileResponse.serializer)
      ..add(MasterSearchRequest.serializer)
      ..add(MasterSearchResult.serializer)
      ..add(MasterServiceResponse.serializer)
      ..add(MasterSummaryResponse.serializer)
      ..add(MasterSummaryResponseMasterTypeEnum.serializer)
      ..add(MediaFileResponse.serializer)
      ..add(MediaFileResponseEntityTypeEnum.serializer)
      ..add(MediaFileResponseMediaTypeEnum.serializer)
      ..add(OblastResponse.serializer)
      ..add(PageMediaFileResponse.serializer)
      ..add(PageResponseBookingResponse.serializer)
      ..add(PageResponseMasterSearchResult.serializer)
      ..add(PageResponseMasterSummaryResponse.serializer)
      ..add(PageResponseReviewResponse.serializer)
      ..add(PageResponseSalonSearchResult.serializer)
      ..add(Pageable.serializer)
      ..add(PageableObject.serializer)
      ..add(PlatformCategoryResponse.serializer)
      ..add(PlatformCategoryUsageResponse.serializer)
      ..add(PublicSalonResponse.serializer)
      ..add(RefreshRequest.serializer)
      ..add(RegisterDeviceTokenRequest.serializer)
      ..add(RegisterIndependentMasterRequest.serializer)
      ..add(RegisterRequest.serializer)
      ..add(RegisterRequestRoleEnum.serializer)
      ..add(RegistrationResponse.serializer)
      ..add(ResendVerificationRequest.serializer)
      ..add(ResetPasswordRequest.serializer)
      ..add(RevenueByDateDto.serializer)
      ..add(RevenueByMasterDto.serializer)
      ..add(RevenueByServiceDto.serializer)
      ..add(RevenueResponse.serializer)
      ..add(ReviewResponse.serializer)
      ..add(SalonResponse.serializer)
      ..add(SalonSearchRequest.serializer)
      ..add(SalonSearchResult.serializer)
      ..add(ScheduleExceptionRequest.serializer)
      ..add(ScheduleExceptionRequestReasonEnum.serializer)
      ..add(ServiceDefinitionResponse.serializer)
      ..add(ServiceTypeResponse.serializer)
      ..add(SortObject.serializer)
      ..add(StatusUpdateRequest.serializer)
      ..add(StatusUpdateRequestCancellationReasonEnum.serializer)
      ..add(SuggestServiceTypeRequest.serializer)
      ..add(UnregisterDeviceTokenRequest.serializer)
      ..add(UpdateProfileRequest.serializer)
      ..add(UpdateSalonRequest.serializer)
      ..add(UpdateServiceDefinitionRequest.serializer)
      ..add(UpdateServicePhotoRequest.serializer)
      ..add(UploadPortfolioPhotoRequest.serializer)
      ..add(UserProfileResponse.serializer)
      ..add(VerifyEmailRequest.serializer)
      ..add(WorkingHoursRequest.serializer)
      ..add(WorkingHoursResponse.serializer)
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(ApprovedCategoryResponse)]),
          () => ListBuilder<ApprovedCategoryResponse>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(AvailableSlotResponse)]),
          () => ListBuilder<AvailableSlotResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(BookingResponse)]),
          () => ListBuilder<BookingResponse>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(CatalogCategoryResponse)]),
          () => ListBuilder<CatalogCategoryResponse>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(CityDistrictResponse)]),
          () => ListBuilder<CityDistrictResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(CityResponse)]),
          () => ListBuilder<CityResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(MasterSearchResult)]),
          () => ListBuilder<MasterSearchResult>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(MasterServiceResponse)]),
          () => ListBuilder<MasterServiceResponse>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(MasterSummaryResponse)]),
          () => ListBuilder<MasterSummaryResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(MediaFileResponse)]),
          () => ListBuilder<MediaFileResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(OblastResponse)]),
          () => ListBuilder<OblastResponse>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(PlatformCategoryUsageResponse)]),
          () => ListBuilder<PlatformCategoryUsageResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(RevenueByMasterDto)]),
          () => ListBuilder<RevenueByMasterDto>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(RevenueByServiceDto)]),
          () => ListBuilder<RevenueByServiceDto>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(RevenueByDateDto)]),
          () => ListBuilder<RevenueByDateDto>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ReviewResponse)]),
          () => ListBuilder<ReviewResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(SalonResponse)]),
          () => ListBuilder<SalonResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(SalonSearchResult)]),
          () => ListBuilder<SalonSearchResult>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(ServiceTypeResponse)]),
          () => ListBuilder<ServiceTypeResponse>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(WorkingHoursResponse)]),
          () => ListBuilder<WorkingHoursResponse>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(WorkingHoursResponse)]),
          () => ListBuilder<WorkingHoursResponse>()))
    .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
